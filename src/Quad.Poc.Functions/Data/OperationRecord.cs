namespace Quad.Poc.Functions.Data;

public sealed record OperationRecord(
    Guid OperationId,
    string TenantId,
    string Status,
    string? ErrorCode,
    string? ErrorMessage,
    string ResourceType,
    string ResourceId,
    DateTime CreatedAt,
    DateTime UpdatedAt);
