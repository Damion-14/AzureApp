namespace Quad.Poc.Worker.Messaging;

public sealed class WorkerOptions
{
    public string TopicName { get; init; } = "quad-poc-bus";

    public string CommandsSubscription { get; init; } = "commands";

    public string TenantDefault { get; init; } = "poc";

    public int ProcessingDelayMs { get; init; } = 200;
}
