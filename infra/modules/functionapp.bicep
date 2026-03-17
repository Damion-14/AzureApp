param location string
param storageAccountName string
param functionAppName string
param appServicePlanName string
param logAnalyticsWorkspaceName string
param appInsightsName string
@secure()
param serviceBusConnectionString string
@secure()
param sqlConnectionString string
param topicName string
param resultsSubscriptionName string
param authEnabled bool = false
param authTenantId string = ''
param authApiClientId string = ''
@secure()
param authApiClientSecret string = ''
param authAllowedClientApplications array = []
param authAllowedAudiences array = []
param authAuthorizedClientsJson string = '[]'
param authReadRole string = 'items.read'
param authWriteRole string = 'items.write'

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  kind: 'functionapp'
  properties: {
    reserved: true
  }
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  sku: {
    name: 'PerGB2018'
  }
  properties: {
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
  }
}

var storageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${listKeys(storage.id, storage.apiVersion).keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
var effectiveAllowedAudiences = !empty(authAllowedAudiences)
  ? authAllowedAudiences
  : empty(authApiClientId)
    ? []
    : [
        'api://${authApiClientId}'
      ]

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNET-ISOLATED|8.0'
      ftpsState: 'FtpsOnly'
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
        }
        {
          name: 'AzureWebJobsStorage'
          value: storageConnectionString
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'ServiceBusConnectionString'
          value: serviceBusConnectionString
        }
        {
          name: 'SqlConnectionString'
          value: sqlConnectionString
        }
        {
          name: 'TopicName'
          value: topicName
        }
        {
          name: 'ResultsSubscription'
          value: resultsSubscriptionName
        }
        {
          name: 'Auth__Enabled'
          value: string(authEnabled)
        }
        {
          name: 'Auth__AuthorizedClientsJson'
          value: authAuthorizedClientsJson
        }
        {
          name: 'Auth__ReadRole'
          value: authReadRole
        }
        {
          name: 'Auth__WriteRole'
          value: authWriteRole
        }
        {
          name: 'Auth__DefaultTenantId'
          value: 'poc'
        }
        {
          name: 'MICROSOFT_PROVIDER_AUTHENTICATION_SECRET'
          value: authApiClientSecret
        }
      ]
    }
  }
}

resource functionAppAuth 'Microsoft.Web/sites/config@2022-09-01' = if (authEnabled) {
  name: 'authsettingsV2'
  parent: functionApp
  properties: {
    platform: {
      enabled: true
      runtimeVersion: '~1'
    }
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'Return401'
      redirectToProvider: 'azureactivedirectory'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: authApiClientId
          clientSecretSettingName: 'MICROSOFT_PROVIDER_AUTHENTICATION_SECRET'
          openIdIssuer: 'https://login.microsoftonline.com/${authTenantId}/v2.0'
        }
        validation: {
          allowedAudiences: effectiveAllowedAudiences
          defaultAuthorizationPolicy: {
            allowedApplications: authAllowedClientApplications
          }
          jwtClaimChecks: {
            allowedClientApplications: authAllowedClientApplications
          }
        }
      }
    }
    login: {
      tokenStore: {
        enabled: false
      }
    }
  }
}

output functionAppName string = functionApp.name
output storageAccountName string = storage.name
