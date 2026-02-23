using Azure.Messaging.ServiceBus;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Quad.Poc.Worker.Messaging;

IHost host = Host.CreateDefaultBuilder(args)
    .ConfigureServices((context, services) =>
    {
        IConfiguration configuration = context.Configuration;
        string serviceBusConnectionString = configuration["ServiceBusConnectionString"]
            ?? throw new InvalidOperationException("Missing ServiceBusConnectionString in configuration.");

        WorkerOptions options = new()
        {
            TopicName = configuration["TopicName"] ?? "quad-poc-bus",
            CommandsSubscription = configuration["CommandsSubscription"] ?? "commands",
            TenantDefault = configuration["TenantDefault"] ?? "poc",
            ProcessingDelayMs = int.TryParse(configuration["ProcessingDelayMs"], out int delay) ? delay : 200
        };

        services.AddSingleton(new ServiceBusClient(serviceBusConnectionString));
        services.AddSingleton(options);
        services.AddHostedService<CommandWorkerService>();
    })
    .Build();

await host.RunAsync();
