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

resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: appServicePlanName
  location: location
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
  }
}

resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: '${storage.name}/default/app-package'
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

var effectiveAllowedAudiences = !empty(authAllowedAudiences)
  ? authAllowedAudiences
  : empty(authApiClientId)
    ? []
    : [
        'api://${authApiClientId}'
      ]
var storageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${listKeys(storage.id, storage.apiVersion).keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: storageConnectionString
        }
        {
          name: 'DEPLOYMENT_STORAGE_CONNECTION_STRING'
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
    functionAppConfig: {
      runtime: {
        name: 'dotnet-isolated'
        version: '8.0'
      }
      scaleAndConcurrency: {
        instanceMemoryMB: 2048
        maximumInstanceCount: 2
      }
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.properties.primaryEndpoints.blob}app-package'
          authentication: {
            type: 'StorageAccountConnectionString'
            storageAccountConnectionStringName: 'DEPLOYMENT_STORAGE_CONNECTION_STRING'
          }
        }
      }
    }
  }
  dependsOn: [
    deploymentContainer
  ]
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
