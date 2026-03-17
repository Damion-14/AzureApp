targetScope = 'subscription'

@description('Deployment location for all resources.')
param location string = 'eastus'

@description('Resource group name for the PoC resources.')
param resourceGroupName string

@description('If true, create the resource group in this deployment.')
param createResourceGroup bool = true

@description('Prefix used for generated resource names.')
param namePrefix string = 'quadpoc'

@description('Service Bus topic name.')
param topicName string = 'quad-poc-bus'

@description('Azure SQL admin login.')
param sqlAdminLogin string

@secure()
@description('Azure SQL admin password.')
param sqlAdminPassword string

@description('Public client IP allowed for SQL access.')
param clientIpAddress string

@description('Enable Microsoft Entra authentication in front of the Function App.')
param authEnabled bool = false

@description('Microsoft Entra tenant ID used by the Function App authentication provider.')
param authTenantId string = ''

@description('Application client ID of the Microsoft Entra app registration that represents the Function API.')
param authApiClientId string = ''

@secure()
@description('Client secret for the Microsoft Entra app registration used by App Service authentication.')
param authApiClientSecret string = ''

@description('Client application IDs that are allowed to call the Function API.')
param authAllowedClientApplications array = []

@description('Audiences allowed for bearer tokens. If empty and auth is enabled, api://<authApiClientId> is used.')
param authAllowedAudiences array = []

@description('JSON array mapping approved client application IDs to application tenant IDs.')
param authAuthorizedClientsJson string = '[]'

@description('Role claim required to read items and operations.')
param authReadRole string = 'items.read'

@description('Role claim required to write items.')
param authWriteRole string = 'items.write'

var suffix = toLower(uniqueString(subscription().subscriptionId, resourceGroupName, namePrefix))
var storageAccountName = take(toLower(replace('${namePrefix}${suffix}sa', '-', '')), 24)
var functionAppName = '${namePrefix}-func-${suffix}'
var appServicePlanName = '${namePrefix}-plan-${suffix}'
var logAnalyticsWorkspaceName = '${namePrefix}-log-${suffix}'
var appInsightsName = '${namePrefix}-appi-${suffix}'
var serviceBusNamespaceName = '${namePrefix}-sb-${suffix}'
var sqlServerName = '${namePrefix}-sql-${suffix}'
var sqlDatabaseName = '${namePrefix}-db'

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = if (createResourceGroup) {
  name: resourceGroupName
  location: location
}

module serviceBus './modules/servicebus.bicep' = {
  name: 'serviceBusStack'
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
  params: {
    location: location
    namespaceName: serviceBusNamespaceName
    topicName: topicName
    commandsSubscriptionName: 'commands'
    resultsSubscriptionName: 'results'
  }
}

module sql './modules/sql.bicep' = {
  name: 'sqlStack'
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
  params: {
    location: location
    serverName: sqlServerName
    databaseName: sqlDatabaseName
    sqlAdminLogin: sqlAdminLogin
    sqlAdminPassword: sqlAdminPassword
    clientIpAddress: clientIpAddress
  }
}

module functionApp './modules/functionapp.bicep' = {
  name: 'functionAppStack'
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
    serviceBus
    sql
  ]
  params: {
    location: location
    storageAccountName: storageAccountName
    functionAppName: functionAppName
    appServicePlanName: appServicePlanName
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    appInsightsName: appInsightsName
    serviceBusConnectionString: serviceBus.outputs.serviceBusConnectionString
    sqlConnectionString: sql.outputs.sqlConnectionString
    topicName: topicName
    resultsSubscriptionName: 'results'
    authEnabled: authEnabled
    authTenantId: authTenantId
    authApiClientId: authApiClientId
    authApiClientSecret: authApiClientSecret
    authAllowedClientApplications: authAllowedClientApplications
    authAllowedAudiences: authAllowedAudiences
    authAuthorizedClientsJson: authAuthorizedClientsJson
    authReadRole: authReadRole
    authWriteRole: authWriteRole
  }
}

output serviceBusConnectionString string = serviceBus.outputs.serviceBusConnectionString
output sqlConnectionString string = sql.outputs.sqlConnectionString
output functionAppName string = functionApp.outputs.functionAppName
output topicName string = topicName
output serviceBusNamespaceName string = serviceBusNamespaceName
output sqlServerName string = sqlServerName
output sqlDatabaseName string = sqlDatabaseName
