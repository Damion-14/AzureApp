using '../main.bicep'

param location = 'eastus'
param resourceGroupName = 'rg-quad-poc-dev'
param createResourceGroup = true
param namePrefix = 'quadpoc'
param topicName = 'quad-poc-bus'
param sqlAdminLogin = 'quadpocadmin'
param sqlAdminPassword = readEnvironmentVariable('SQL_ADMIN_PASSWORD')
param clientIpAddress = readEnvironmentVariable('CLIENT_IP_ADDRESS')
param authEnabled = false
param authTenantId = readEnvironmentVariable('AUTH_TENANT_ID', '')
param authApiClientId = readEnvironmentVariable('AUTH_API_CLIENT_ID', '')
param authApiClientSecret = readEnvironmentVariable('AUTH_API_CLIENT_SECRET', '')
param authAllowedClientApplications = empty(readEnvironmentVariable('AUTH_ALLOWED_CLIENT_APPLICATIONS', ''))
  ? []
  : split(readEnvironmentVariable('AUTH_ALLOWED_CLIENT_APPLICATIONS', ''), ',')
param authAuthorizedClientsJson = empty(readEnvironmentVariable('AUTH_AUTHORIZED_CLIENTS_JSON', ''))
  ? '[]'
  : readEnvironmentVariable('AUTH_AUTHORIZED_CLIENTS_JSON', '')
param authReadRole = 'items.read'
param authWriteRole = 'items.write'
