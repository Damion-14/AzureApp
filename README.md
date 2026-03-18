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

## Minimal Azure test flow

This is the shortest path to get the app running for manual testing:

1. Log in to Azure CLI and choose the subscription.
2. Deploy infrastructure with the PowerShell script.
3. Publish the Azure Function App.
4. Apply the SQL schema.
5. Run the worker locally.
6. Call the deployed Function App from Postman.

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
```

### 5. Run the worker locally

The worker reads from the `commands` Service Bus subscription and writes results back to the topic.

```powershell
.\scripts\run-worker.ps1 -ServiceBusConnectionString "<service-bus-connection-string>"
```

You can also run `Quad.Poc.Worker` from Visual Studio. The project includes a Development launch profile and reads `appsettings.Development.json`.

### 6. Test from Postman

Use this request:

- Method: `PUT`
- URL: `https://<functionAppName>.azurewebsites.net/v1/items/item-1001`
- Headers:
  - `Content-Type: application/json`
  - `X-Tenant-Id: poc`
  - `Idempotency-Key: idem-1001`
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

- `GET {{StatusUrl}}`
- `GET {{ResourceUrl}}` with header `X-Tenant-Id: poc`

### 7. Clean up

Delete the resource group when done:

```powershell
az group delete --name "rg-azure-app-test" --yes
```

## Configure and run Function App locally

1. Copy `src/Quad.Poc.Functions/local.settings.sample.json` to `local.settings.json`.
2. Fill in:
- `ServiceBusConnectionString`
- `SqlConnectionString`
- `Auth__Enabled` (`false` for local header-based testing, `true` to test App Service auth headers locally)
- `Auth__AuthorizedClientsJson` (maps approved Entra client app IDs to application tenant IDs)

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

## API authentication and authorization

The Function App can now be protected with Microsoft Entra ID through App Service Authentication.

- Azure-side gate: `infra/modules/functionapp.bicep` configures `authsettingsV2` when `authEnabled=true`.
- Client allow-list: set `authAllowedClientApplications` to the Entra app IDs that may call the API.
- In-app tenant mapping: set `authAuthorizedClientsJson` to a JSON array like `[{"clientId":"<app-id>","tenantId":"tenant-a","name":"Client A"}]`.
- Role checks: callers must have the Entra app role claims configured by `authReadRole` and `authWriteRole`.

When auth is enabled, the Functions app no longer trusts caller-supplied `X-Tenant-Id` for authorization. Tenant context comes from the authenticated client app mapping instead.
