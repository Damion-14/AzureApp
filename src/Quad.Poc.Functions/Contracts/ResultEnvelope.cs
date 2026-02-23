using System.Text.Json;

namespace Quad.Poc.Functions.Contracts;

public sealed class ResultEnvelope
{
    public required string ResultType { get; init; }

    public required Guid OperationId { get; init; }

    public required string TenantId { get; init; }

    public required string ResourceType { get; init; }

    public required string ResourceId { get; init; }

    public required JsonElement Snapshot { get; init; }

    public required string Status { get; init; }

    public string? ErrorCode { get; init; }

    public string? ErrorMessage { get; init; }
}
