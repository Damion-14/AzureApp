namespace Quad.Poc.Functions.Data;

public enum OperationCreateOutcome
{
    Created = 0,
    ReplaySameHash = 1,
    ConflictDifferentHash = 2
}

public sealed record OperationCreateResult(OperationCreateOutcome Outcome, Guid OperationId);
