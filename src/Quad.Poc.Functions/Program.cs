using Azure.Messaging.ServiceBus;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Quad.Poc.Functions.Auth;
using Quad.Poc.Functions.Data;
using Quad.Poc.Functions.Messaging;

IHost host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices((context, services) =>
    {
        IConfiguration configuration = context.Configuration;

        string serviceBusConnectionString = configuration["ServiceBusConnectionString"]
            ?? throw new InvalidOperationException("Missing ServiceBusConnectionString setting.");
        string sqlConnectionString = configuration["SqlConnectionString"]
            ?? throw new InvalidOperationException("Missing SqlConnectionString setting.");
        string topicName = configuration["TopicName"] ?? "quad-poc-bus";
        AuthOptions authOptions = AuthOptions.FromConfiguration(configuration);

        services.AddSingleton(new SqlRepositoryOptions(sqlConnectionString));
        services.AddSingleton<SqlRepository>();
        services.AddSingleton(new ServiceBusClient(serviceBusConnectionString));
        services.AddSingleton(new TopicPublisherOptions(topicName));
        services.AddSingleton<TopicPublisher>();
        services.AddSingleton(authOptions);
        services.AddSingleton<RequestAuthorizer>();
    })
    .Build();

host.Run();
