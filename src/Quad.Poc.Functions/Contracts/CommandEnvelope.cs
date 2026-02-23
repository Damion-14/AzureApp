using System.Text.Json;

namespace Quad.Poc.Functions.Contracts;

public sealed class CommandEnvelope
{
    public required string CommandType { get; init; }

    public required Guid CommandId { get; init; }

    public required Guid OperationId { get; init; }

    public required string TenantId { get; init; }

    public required string IdempotencyKey { get; init; }

    public required string ResourceId { get; init; }

    public required JsonElement Payload { get; init; }
}
