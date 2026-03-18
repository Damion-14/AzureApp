param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,
    [Parameter(Mandatory = $true)]
    [string]$ClientName,
    [string]$KeyName = "default",
    [string]$ClientId,
    [string]$ApiKeyId
)

$ErrorActionPreference = "Stop"

if (-not $ClientId) {
    $ClientId = (New-Guid).Guid
}

if (-not $ApiKeyId) {
    $ApiKeyId = (New-Guid).Guid
}

$plainKey = -join (1..32 | ForEach-Object { '{0:x2}' -f (Get-Random -Minimum 0 -Maximum 256) })
$tempFile = New-TemporaryFile

try {
    Set-Content -Path $tempFile.FullName -Value $plainKey -NoNewline -Encoding ascii
    $hashHex = (Get-FileHash -Path $tempFile.FullName -Algorithm SHA256).Hash
}
finally {
    Remove-Item -Path $tempFile.FullName -ErrorAction SilentlyContinue
}

@"
-- Run this SQL against your Azure SQL database.
DECLARE @clientId UNIQUEIDENTIFIER = '$ClientId';

IF NOT EXISTS (SELECT 1 FROM dbo.clients WHERE clientId = @clientId)
BEGIN
    INSERT INTO dbo.clients (clientId, tenantId, name)
    VALUES (@clientId, '$TenantId', '$ClientName');
END;

INSERT INTO dbo.api_keys (apiKeyId, clientId, keyName, keyHash)
VALUES ('$ApiKeyId', @clientId, '$KeyName', 0x$hashHex);
"@

Write-Host ""
Write-Host "Plaintext API key (shown once):" -ForegroundColor Yellow
Write-Host $plainKey
