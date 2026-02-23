using System.Data;
using System.Security.Cryptography;
using Dapper;
using Microsoft.Data.SqlClient;
using Quad.Poc.Functions.Contracts;

namespace Quad.Poc.Functions.Data;

public sealed record SqlRepositoryOptions(string ConnectionString);

internal sealed record ExistingOperation(Guid OperationId, byte[] RequestHash);

public sealed class SqlRepository
{
    private readonly string _connectionString;

    public SqlRepository(SqlRepositoryOptions options)
    {
        _connectionString = options.ConnectionString;
    }

    public async Task<OperationCreateResult> CreateOperationAsync(
        string tenantId,
        string idempotencyKey,
        byte[] requestHash,
        string resourceType,
        string resourceId,
        CancellationToken cancellationToken)
    {
        const string existingSql = """
            SELECT operationId, requestHash
            FROM operations WITH (UPDLOCK, HOLDLOCK)
            WHERE tenantId = @tenantId AND idempotencyKey = @idempotencyKey;
            """;

        const string insertSql = """
            INSERT INTO operations
            (
                operationId,
                tenantId,
                idempotencyKey,
                requestHash,
                status,
                resourceType,
                resourceId,
                createdAt,
                updatedAt
            )
            VALUES
            (
                @operationId,
                @tenantId,
                @idempotencyKey,
                @requestHash,
                'accepted',
                @resourceType,
                @resourceId,
                SYSUTCDATETIME(),
                SYSUTCDATETIME()
            );
            """;

        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(IsolationLevel.Serializable, cancellationToken);

        ExistingOperation? existing = await connection.QuerySingleOrDefaultAsync<ExistingOperation>(new CommandDefinition(
            existingSql,
            new { tenantId, idempotencyKey },
            transaction,
            cancellationToken: cancellationToken));

        if (existing is not null)
        {
            await transaction.CommitAsync(cancellationToken);
            bool sameHash = existing.RequestHash.Length == requestHash.Length &&
                CryptographicOperations.FixedTimeEquals(existing.RequestHash, requestHash);

            return sameHash
                ? new OperationCreateResult(OperationCreateOutcome.ReplaySameHash, existing.OperationId)
                : new OperationCreateResult(OperationCreateOutcome.ConflictDifferentHash, existing.OperationId);
        }

        Guid operationId = Guid.NewGuid();

        await connection.ExecuteAsync(new CommandDefinition(
            insertSql,
            new
            {
                operationId,
                tenantId,
                idempotencyKey,
                requestHash,
                resourceType,
                resourceId
            },
            transaction,
            cancellationToken: cancellationToken));

        await transaction.CommitAsync(cancellationToken);
        return new OperationCreateResult(OperationCreateOutcome.Created, operationId);
    }

    public async Task<OperationRecord?> GetOperationAsync(Guid operationId, CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                operationId,
                tenantId,
                status,
                errorCode,
                errorMessage,
                resourceType,
                resourceId,
                createdAt,
                updatedAt
            FROM operations
            WHERE operationId = @operationId;
            """;

        await using var connection = new SqlConnection(_connectionString);
        return await connection.QuerySingleOrDefaultAsync<OperationRecord>(new CommandDefinition(
            sql,
            new { operationId },
            cancellationToken: cancellationToken));
    }

    public async Task<SnapshotRecord?> GetSnapshotAsync(
        string tenantId,
        string resourceType,
        string resourceId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT snapshotJson, etag
            FROM resource_snapshots
            WHERE tenantId = @tenantId AND resourceType = @resourceType AND resourceId = @resourceId;
            """;

        await using var connection = new SqlConnection(_connectionString);
        return await connection.QuerySingleOrDefaultAsync<SnapshotRecord>(new CommandDefinition(
            sql,
            new
            {
                tenantId,
                resourceType,
                resourceId
            },
            cancellationToken: cancellationToken));
    }

    public async Task ApplyResultAsync(ResultEnvelope result, string snapshotJson, CancellationToken cancellationToken)
    {
        const string updateSnapshotSql = """
            UPDATE resource_snapshots
            SET snapshotJson = @snapshotJson, updatedAt = SYSUTCDATETIME()
            WHERE tenantId = @tenantId AND resourceType = @resourceType AND resourceId = @resourceId;
            """;

        const string insertSnapshotSql = """
            INSERT INTO resource_snapshots
            (
                tenantId,
                resourceType,
                resourceId,
                snapshotJson,
                updatedAt
            )
            VALUES
            (
                @tenantId,
                @resourceType,
                @resourceId,
                @snapshotJson,
                SYSUTCDATETIME()
            );
            """;

        const string updateOperationSql = """
            UPDATE operations
            SET
                status = @status,
                errorCode = @errorCode,
                errorMessage = @errorMessage,
                updatedAt = SYSUTCDATETIME()
            WHERE operationId = @operationId;
            """;

        string normalizedStatus = string.Equals(result.Status, "succeeded", StringComparison.OrdinalIgnoreCase)
            ? "succeeded"
            : "failed";

        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        if (normalizedStatus == "succeeded")
        {
            int rowsUpdated = await connection.ExecuteAsync(new CommandDefinition(
                updateSnapshotSql,
                new
                {
                    result.TenantId,
                    result.ResourceType,
                    result.ResourceId,
                    snapshotJson
                },
                transaction,
                cancellationToken: cancellationToken));

            if (rowsUpdated == 0)
            {
                await connection.ExecuteAsync(new CommandDefinition(
                    insertSnapshotSql,
                    new
                    {
                        result.TenantId,
                        result.ResourceType,
                        result.ResourceId,
                        snapshotJson
                    },
                    transaction,
                    cancellationToken: cancellationToken));
            }
        }

        await connection.ExecuteAsync(new CommandDefinition(
            updateOperationSql,
            new
            {
                status = normalizedStatus,
                errorCode = normalizedStatus == "succeeded" ? null : result.ErrorCode,
                errorMessage = normalizedStatus == "succeeded" ? null : result.ErrorMessage,
                operationId = result.OperationId
            },
            transaction,
            cancellationToken: cancellationToken));

        await transaction.CommitAsync(cancellationToken);
    }

    public async Task MarkOperationFailedAsync(
        Guid operationId,
        string errorCode,
        string errorMessage,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE operations
            SET
                status = 'failed',
                errorCode = @errorCode,
                errorMessage = @errorMessage,
                updatedAt = SYSUTCDATETIME()
            WHERE operationId = @operationId;
            """;

        await using var connection = new SqlConnection(_connectionString);
        await connection.ExecuteAsync(new CommandDefinition(
            sql,
            new
            {
                operationId,
                errorCode,
                errorMessage
            },
            cancellationToken: cancellationToken));
    }
}
