using '../main.bicep'

param location = 'eastus'
param resourceGroupName = 'rg-quad-poc-dev'
param createResourceGroup = true
param namePrefix = 'quadpoc'
param topicName = 'quad-poc-bus'
param sqlAdminLogin = 'quadpocadmin'
param sqlAdminPassword = readEnvironmentVariable('SQL_ADMIN_PASSWORD')
param clientIpAddress = readEnvironmentVariable('CLIENT_IP_ADDRESS')
