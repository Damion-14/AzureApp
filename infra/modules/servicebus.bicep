param location string
param namespaceName string
param topicName string
param commandsSubscriptionName string = 'commands'
param resultsSubscriptionName string = 'results'

resource namespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: namespaceName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
}

resource topic 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = {
  parent: namespace
  name: topicName
}

resource commandsSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: topic
  name: commandsSubscriptionName
}

resource resultsSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: topic
  name: resultsSubscriptionName
}

resource commandsRuleDefault 'Microsoft.ServiceBus/namespaces/topics/subscriptions/rules@2022-10-01-preview' = {
  parent: commandsSubscription
  name: 'CommandFilter'
  properties: {
    filterType: 'SqlFilter'
    sqlFilter: {
      sqlExpression: 'messageType = \'command\''
    }
  }
}

resource resultsRuleDefault 'Microsoft.ServiceBus/namespaces/topics/subscriptions/rules@2022-10-01-preview' = {
  parent: resultsSubscription
  name: 'ResultFilter'
  properties: {
    filterType: 'SqlFilter'
    sqlFilter: {
      sqlExpression: 'messageType = \'result\''
    }
  }
}

resource rootManageSharedAccessKey 'Microsoft.ServiceBus/namespaces/authorizationRules@2022-10-01-preview' existing = {
  parent: namespace
  name: 'RootManageSharedAccessKey'
}

output serviceBusConnectionString string = 'Endpoint=sb://${namespace.name}.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=${listKeys(rootManageSharedAccessKey.id, rootManageSharedAccessKey.apiVersion).primaryKey}'
