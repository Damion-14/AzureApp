param(
    [string]$BaseUrl = "http://localhost:7071",
    [Parameter(Mandatory = $true)]
    [string]$ApiKey,
    [string]$ItemId = "item-1001",
    [string]$IdempotencyKey = "idem-1001"
)

$ErrorActionPreference = "Stop"

$payload = @{
    itemId = $ItemId
    name = "PoC Item"
    quantity = 4
    uom = "EA"
    lastUpdatedBy = "manual-test"
} | ConvertTo-Json -Depth 10

$putUrl = "$BaseUrl/v1/items/$ItemId"
$putHeaders = @{
    "Content-Type" = "application/json"
    "X-Api-Key" = $ApiKey
    "Idempotency-Key" = $IdempotencyKey
}

Write-Host "PUT first request..."
$firstResponse = Invoke-RestMethod -Method Put -Uri $putUrl -Headers $putHeaders -Body $payload
$operationId = $firstResponse.operationId
Write-Host "OperationId: $operationId"

Write-Host "PUT replay with same idempotency key..."
$secondResponse = Invoke-RestMethod -Method Put -Uri $putUrl -Headers $putHeaders -Body $payload
if ($secondResponse.operationId -ne $operationId) {
    throw "Replay did not return same operationId. expected=$operationId actual=$($secondResponse.operationId)"
}
Write-Host "Replay returned same operationId."

$operationUrl = "$BaseUrl/v1/operations/$operationId"
Write-Host "Polling operation status..."
for ($i = 0; $i -lt 30; $i++) {
    $op = Invoke-RestMethod -Method Get -Uri $operationUrl -Headers @{ "X-Api-Key" = $ApiKey }
    Write-Host "Status: $($op.status)"
    if ($op.status -eq "succeeded") {
        break
    }
    if ($op.status -eq "failed") {
        throw "Operation failed: $($op.errorCode) $($op.errorMessage)"
    }
    Start-Sleep -Seconds 1
}

$itemUrl = "$BaseUrl/v1/items/$ItemId"
Write-Host "GET item snapshot..."
$item = Invoke-RestMethod -Method Get -Uri $itemUrl -Headers @{ "X-Api-Key" = $ApiKey }
$item | ConvertTo-Json -Depth 20
