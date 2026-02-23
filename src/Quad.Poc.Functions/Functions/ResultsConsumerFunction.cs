using System.Text.Json;
using Azure.Messaging.ServiceBus;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Quad.Poc.Functions.Contracts;
using Quad.Poc.Functions.Data;

namespace Quad.Poc.Functions.Functions;

public sealed class ResultsConsumerFunction
{
    private readonly SqlRepository _repository;
    private readonly ILogger<ResultsConsumerFunction> _logger;

    public ResultsConsumerFunction(SqlRepository repository, ILogger<ResultsConsumerFunction> logger)
    {
        _repository = repository;
        _logger = logger;
    }

    [Function("ResultsConsumer")]
    public async Task Run(
        [ServiceBusTrigger("%TopicName%", "%ResultsSubscription%", Connection = "ServiceBusConnectionString", AutoCompleteMessages = false)]
        ServiceBusReceivedMessage message,
        ServiceBusMessageActions messageActions,
        FunctionContext context)
    {
        try
        {
            ResultEnvelope? result = message.Body.ToObjectFromJson<ResultEnvelope>(new JsonSerializerOptions(JsonSerializerDefaults.Web));
            if (result is null)
            {
                throw new InvalidOperationException("Result payload is empty.");
            }

            await _repository.ApplyResultAsync(
                result,
                result.Snapshot.GetRawText(),
                context.CancellationToken);

            await messageActions.CompleteMessageAsync(message, context.CancellationToken);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to process result message {MessageId}", message.MessageId);
            await messageActions.DeadLetterMessageAsync(
                message,
                deadLetterReason: "ProcessingFailed",
                deadLetterErrorDescription: ex.Message,
                cancellationToken: context.CancellationToken);
        }
    }
}
