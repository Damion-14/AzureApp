using System.Text.Json;
using Azure.Messaging.ServiceBus;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Quad.Poc.Worker.Contracts;

namespace Quad.Poc.Worker.Messaging;

public sealed class CommandWorkerService : BackgroundService, IAsyncDisposable
{
    private readonly ServiceBusClient _serviceBusClient;
    private readonly WorkerOptions _options;
    private readonly ILogger<CommandWorkerService> _logger;
    private ServiceBusProcessor? _processor;
    private ServiceBusSender? _sender;

    public CommandWorkerService(
        ServiceBusClient serviceBusClient,
        WorkerOptions options,
        ILogger<CommandWorkerService> logger)
    {
        _serviceBusClient = serviceBusClient;
        _options = options;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _sender = _serviceBusClient.CreateSender(_options.TopicName);
        _processor = _serviceBusClient.CreateProcessor(
            _options.TopicName,
            _options.CommandsSubscription,
            new ServiceBusProcessorOptions
            {
                AutoCompleteMessages = false,
                MaxConcurrentCalls = 1
            });

        _processor.ProcessMessageAsync += ProcessMessageAsync;
        _processor.ProcessErrorAsync += ProcessErrorAsync;
        await _processor.StartProcessingAsync(stoppingToken);

        try
        {
            await Task.Delay(Timeout.Infinite, stoppingToken);
        }
        catch (TaskCanceledException)
        {
            _logger.LogInformation("Worker cancellation requested.");
        }
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        if (_processor is not null)
        {
            await _processor.StopProcessingAsync(cancellationToken);
        }

        await base.StopAsync(cancellationToken);
    }

    private async Task ProcessMessageAsync(ProcessMessageEventArgs args)
    {
        string messageType = args.Message.ApplicationProperties.TryGetValue("messageType", out object? typeObj)
            ? Convert.ToString(typeObj) ?? string.Empty
            : string.Empty;

        if (!string.Equals(messageType, "command", StringComparison.OrdinalIgnoreCase))
        {
            await args.CompleteMessageAsync(args.Message, args.CancellationToken);
            return;
        }

        CommandEnvelope? command = null;
        try
        {
            JsonSerializerOptions jsonOptions = new(JsonSerializerDefaults.Web);
            command = args.Message.Body.ToObjectFromJson<CommandEnvelope>(jsonOptions);
            if (command is null)
            {
                throw new InvalidOperationException("Command message body is empty.");
            }

            _logger.LogInformation(
                "Processing command {CommandId} for operation {OperationId} resource {ResourceId}",
                command.CommandId,
                command.OperationId,
                command.ResourceId);

            await Task.Delay(_options.ProcessingDelayMs, args.CancellationToken);

            ResultEnvelope result = new()
            {
                ResultType = "Item.Snapshot",
                OperationId = command.OperationId,
                TenantId = string.IsNullOrWhiteSpace(command.TenantId) ? _options.TenantDefault : command.TenantId,
                ResourceType = "Item",
                ResourceId = command.ResourceId,
                Snapshot = command.Payload,
                Status = "succeeded"
            };

            ServiceBusMessage resultMessage = new(BinaryData.FromObjectAsJson(result, new JsonSerializerOptions(JsonSerializerDefaults.Web)))
            {
                ContentType = "application/json",
                MessageId = Guid.NewGuid().ToString(),
                CorrelationId = command.OperationId.ToString(),
                Subject = result.ResultType
            };

            resultMessage.ApplicationProperties["messageType"] = "result";
            await _sender!.SendMessageAsync(resultMessage, args.CancellationToken);
            await args.CompleteMessageAsync(args.Message, args.CancellationToken);
        }
        catch (Exception ex)
        {
            _logger.LogError(
                ex,
                "Failed processing message {MessageId} for operation {OperationId}",
                args.Message.MessageId,
                command?.OperationId);

            await args.AbandonMessageAsync(args.Message, cancellationToken: args.CancellationToken);
        }
    }

    private Task ProcessErrorAsync(ProcessErrorEventArgs args)
    {
        _logger.LogError(
            args.Exception,
            "Service Bus processor error. Entity: {EntityPath}, Namespace: {Namespace}",
            args.EntityPath,
            args.FullyQualifiedNamespace);

        return Task.CompletedTask;
    }

    public async ValueTask DisposeAsync()
    {
        if (_processor is not null)
        {
            _processor.ProcessMessageAsync -= ProcessMessageAsync;
            _processor.ProcessErrorAsync -= ProcessErrorAsync;
            await _processor.DisposeAsync();
        }

        if (_sender is not null)
        {
            await _sender.DisposeAsync();
        }
    }
}
