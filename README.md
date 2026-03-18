# AzureApp PoC

End-to-end PoC for idempotent item upsert using:

- Azure Functions (.NET isolated)
- Azure Service Bus Topic + Subscriptions
- Azure SQL (operations + snapshot tables)
- Custom API key authentication backed by Azure SQL
- Local worker console app
- Bicep for infrastructure

## Project layout

- `infra/` Bicep templates and deployment script
- `db/` SQL schema scripts
- `src/Quad.Poc.Functions/` Function App (HTTP + results consumer)
- `src/Quad.Poc.Worker/` local worker for commands subscription
- `scripts/` helper scripts for worker run and manual test

## Minimal Azure test flow

This is the shortest path to get the app running for manual testing:

1. Log in to Azure CLI and choose the subscription.
2. Deploy infrastructure with the PowerShell script.
3. Publish the Azure Function App.
4. Apply the SQL schema.
5. Create at least one client and API key in SQL.
6. Run the worker locally.
7. Call the deployed Function App with `X-Api-Key`.

### 1. Azure login

```powershell
az login
az account set --subscription "<subscription-guid>"
```

### 2. Deploy infrastructure

```powershell
.\infra\scripts\deploy.ps1 `
  -SubscriptionId "<subscription-guid>" `
  -ResourceGroupName "rg-azure-app-test" `
  -NamePrefix "azureapptest" `
  -Location "eastus" `
  -SqlAdminPassword "<strong-password>"
```

Capture these values from the deployment output:

- `functionAppName`
- `serviceBusConnectionString`
- `sqlServerName`
- `sqlDatabaseName`

### 3. Publish the Function App

Install Azure Functions Core Tools if needed, then publish from the Functions project folder:

```powershell
cd .\src\Quad.Poc.Functions
$env:FUNCTIONS_WORKER_RUNTIME = "dotnet-isolated"
func azure functionapp publish "<functionAppName>" --dotnet-isolated
cd ..\..
```

### 4. Apply the SQL schema

```powershell
sqlcmd -S "<sqlServerName>.database.windows.net" `
  -d "<sqlDatabaseName>" `
  -U "quadpocadmin" `
  -P "<strong-password>" `
  -C `
  -i ".\db\001_schema.sql"

sqlcmd -S "<sqlServerName>.database.windows.net" `
  -d "<sqlDatabaseName>" `
  -U "quadpocadmin" `
  -P "<strong-password>" `
  -C `
  -i ".\db\002_client_registry.sql"

sqlcmd -S "<sqlServerName>.database.windows.net" `
  -d "<sqlDatabaseName>" `
  -U "quadpocadmin" `
  -P "<strong-password>" `
  -C `
  -i ".\db\003_api_keys.sql"
```

### 5. Create a client and API key

Use the helper script to generate a plaintext API key and matching SQL:

```powershell
.\scripts\new-client-api-key.ps1 `
  -TenantId "tenant-a" `
  -ClientName "Client A" `
  -KeyName "default"
```

The script prints:

- a plaintext API key to hand to the client
- SQL to insert the client and hashed key into Azure SQL

Run the SQL it prints against your database before testing the API.

### 6. Run the worker locally

The worker reads from the `commands` Service Bus subscription and writes results back to the topic.

```powershell
.\scripts\run-worker.ps1 -ServiceBusConnectionString "<service-bus-connection-string>"
```

You can also run `Quad.Poc.Worker` from Visual Studio. The project includes a Development launch profile and reads `appsettings.Development.json`.

### 7. Test from Postman

Use this request:

- Method: `PUT`
- URL: `https://<functionAppName>.azurewebsites.net/v1/items/item-1001`
- Headers:
  - `Content-Type: application/json`
  - `Idempotency-Key: idem-1001`
  - `X-Api-Key: <plaintext-api-key>`
- Body:

```json
{
  "itemId": "item-1001",
  "name": "PoC Item",
  "quantity": 4,
  "uom": "EA",
  "lastUpdatedBy": "manual-test"
}
```

Expected response:

```json
{
  "OperationId": "<guid>",
  "StatusUrl": "https://<functionAppName>.azurewebsites.net/v1/operations/<guid>",
  "ResourceUrl": "https://<functionAppName>.azurewebsites.net/v1/items/item-1001"
}
```

Then:

- `GET https://<functionAppName>.azurewebsites.net/v1/operations/<guid>` with the same API key
- `GET https://<functionAppName>.azurewebsites.net/v1/items/item-1001` with the same API key

### 8. Clean up

Delete the resource group when done:

```powershell
az group delete --name "rg-azure-app-test" --yes
```

## Configure and run Function App locally

1. Copy `src/Quad.Poc.Functions/local.settings.sample.json` to `local.settings.json`.
2. Fill in:
- `ServiceBusConnectionString`
- `SqlConnectionString`

Then create a local client and API key with `.\scripts\new-client-api-key.ps1` and insert the generated SQL into your local or Azure SQL database.

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
.\scripts\test-poc.ps1 -BaseUrl "http://localhost:7071" -ApiKey "<plaintext-api-key>"
```

Or via curl/bash:

```bash
export API_KEY="<plaintext-api-key>"
./scripts/test-poc.sh
```

This performs:

1. `PUT /v1/items/{itemId}` (first write) -> expects `202`
2. Replay same PUT with same `Idempotency-Key` -> expects same `operationId`
3. Poll `GET /v1/operations/{operationId}` until `succeeded`
4. `GET /v1/items/{itemId}` -> expects full snapshot JSON

## API authentication and authorization

Each request must include `X-Api-Key`. The Function App hashes the presented key, looks it up in SQL, resolves the canonical client record, and derives the `tenantId` used for item and operation isolation.

- Canonical clients live in `dbo.clients`.
- API keys live in `dbo.api_keys` and are stored as hashes only.
- Multiple keys may exist per client so you can rotate without downtime.
- Disabled clients, inactive keys, revoked keys, and expired keys are rejected before the business operation runs.
