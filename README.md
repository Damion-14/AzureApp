# AzureApp PoC

End-to-end PoC for idempotent item upsert using:

- Azure Functions (.NET isolated)
- Azure Service Bus Topic + Subscriptions
- Azure SQL (operations + snapshot tables)
- Local worker console app
- Bicep for infrastructure

## Project layout

- `infra/` Bicep templates and deployment script
- `db/` SQL schema scripts
- `src/Quad.Poc.Functions/` Function App (HTTP + results consumer)
- `src/Quad.Poc.Worker/` local worker for commands subscription
- `scripts/` helper scripts for worker run and manual test

## Deploy infrastructure

1. Authenticate Azure CLI and choose subscription.
2. Run:

```powershell
.\infra\scripts\deploy.ps1 `
  -SubscriptionId "<subscription-guid>" `
  -SqlAdminPassword "<strong-password>"
```

Deployment outputs include:

- `serviceBusConnectionString`
- `sqlConnectionString`
- `functionAppName`
- `topicName`

## Apply SQL schema

Use Azure Data Studio, SSMS, or `sqlcmd` to execute:

- `db/001_schema.sql`

## Configure and run Function App locally

1. Copy `src/Quad.Poc.Functions/local.settings.sample.json` to `local.settings.json`.
2. Fill in:
- `ServiceBusConnectionString`
- `SqlConnectionString`

3. Run:

```powershell
dotnet run --project .\src\Quad.Poc.Functions\Quad.Poc.Functions.csproj
```

## Run worker locally

```powershell
.\scripts\run-worker.ps1 -ServiceBusConnectionString "<service-bus-conn-string>"
```

## Manual test

```powershell
.\scripts\test-poc.ps1 -BaseUrl "http://localhost:7071"
```

Or via curl/bash:

```bash
./scripts/test-poc.sh
```

This performs:

1. `PUT /v1/items/{itemId}` (first write) -> expects `202`
2. Replay same PUT with same `Idempotency-Key` -> expects same `operationId`
3. Poll `GET /v1/operations/{operationId}` until `succeeded`
4. `GET /v1/items/{itemId}` -> expects full snapshot JSON
