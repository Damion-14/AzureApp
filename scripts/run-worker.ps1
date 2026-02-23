param(
    [Parameter(Mandatory = $true)]
    [string]$ServiceBusConnectionString,
    [string]$TopicName = "quad-poc-bus",
    [string]$CommandsSubscription = "commands",
    [string]$TenantDefault = "poc",
    [int]$ProcessingDelayMs = 200
)

$ErrorActionPreference = "Stop"

$env:ServiceBusConnectionString = $ServiceBusConnectionString
$env:TopicName = $TopicName
$env:CommandsSubscription = $CommandsSubscription
$env:TenantDefault = $TenantDefault
$env:ProcessingDelayMs = $ProcessingDelayMs

dotnet run --project .\src\Quad.Poc.Worker\Quad.Poc.Worker.csproj
