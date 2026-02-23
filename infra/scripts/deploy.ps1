param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    [string]$Location = "eastus",
    [string]$ResourceGroupName = "rg-quad-poc-dev",
    [string]$NamePrefix = "quadpoc",
    [string]$SqlAdminLogin = "quadpocadmin",
    [Parameter(Mandatory = $true)]
    [string]$SqlAdminPassword,
    [string]$TopicName = "quad-poc-bus",
    [switch]$UseExistingResourceGroup
)

$ErrorActionPreference = "Stop"

$templateFile = Join-Path $PSScriptRoot "..\main.bicep"
$clientIpAddress = (Invoke-RestMethod -Uri "https://api.ipify.org?format=json").ip
$createResourceGroup = -not $UseExistingResourceGroup

az account set --subscription $SubscriptionId

az deployment sub create `
  --name "quad-poc-$(Get-Date -Format 'yyyyMMddHHmmss')" `
  --location $Location `
  --template-file $templateFile `
  --parameters `
      location=$Location `
      resourceGroupName=$ResourceGroupName `
      createResourceGroup=$createResourceGroup `
      namePrefix=$NamePrefix `
      topicName=$TopicName `
      sqlAdminLogin=$SqlAdminLogin `
      sqlAdminPassword=$SqlAdminPassword `
      clientIpAddress=$clientIpAddress
