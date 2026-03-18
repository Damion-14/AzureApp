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
  }
}

output serviceBusConnectionString string = serviceBus.outputs.serviceBusConnectionString
output sqlConnectionString string = sql.outputs.sqlConnectionString
output functionAppName string = functionApp.outputs.functionAppName
output topicName string = topicName
output serviceBusNamespaceName string = serviceBusNamespaceName
output sqlServerName string = sqlServerName
output sqlDatabaseName string = sqlDatabaseName
