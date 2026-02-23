using System.Text.Json;
using Azure.Messaging.ServiceBus;
using Quad.Poc.Functions.Contracts;

namespace Quad.Poc.Functions.Messaging;

public sealed record TopicPublisherOptions(string TopicName);

public sealed class TopicPublisher : IAsyncDisposable
{
    private readonly ServiceBusSender _sender;

    public TopicPublisher(ServiceBusClient client, TopicPublisherOptions options)
    {
        _sender = client.CreateSender(options.TopicName);
    }

    public async Task PublishCommandAsync(CommandEnvelope command, CancellationToken cancellationToken)
    {
        ServiceBusMessage message = new(BinaryData.FromObjectAsJson(command, new JsonSerializerOptions(JsonSerializerDefaults.Web)))
        {
            ContentType = "application/json",
            MessageId = command.CommandId.ToString(),
            CorrelationId = command.OperationId.ToString(),
            Subject = command.CommandType
        };

        message.ApplicationProperties["messageType"] = "command";
        await _sender.SendMessageAsync(message, cancellationToken);
    }

    public ValueTask DisposeAsync()
    {
        return _sender.DisposeAsync();
    }
}
