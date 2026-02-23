namespace Quad.Poc.Functions.Contracts;

public sealed record AcceptedOperationResponse(Guid OperationId, string StatusUrl, string ResourceUrl);

public sealed record OperationStatusResponse(
    Guid OperationId,
    string TenantId,
    string Status,
    string? ErrorCode,
    string? ErrorMessage,
    string ResourceType,
    string ResourceId,
    DateTime CreatedAt,
    DateTime UpdatedAt,
    string ResourceUrl);

public sealed record ApiErrorResponse(string Code, string Message);
