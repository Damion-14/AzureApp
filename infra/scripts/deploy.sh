#!/bin/bash

# Azure Bicep deployment script (bash version)
# Usage: ./deploy.sh <SubscriptionId> <SqlAdminPassword>

set -e

# Parameters
SUBSCRIPTION_ID="${1:-}"
SQL_ADMIN_PASSWORD="${2:-}"
LOCATION="${3:-eastus}"
RESOURCE_GROUP_NAME="${4:-rg-quad-poc-dev}"
NAME_PREFIX="${5:-quadpoc}"
SQL_ADMIN_LOGIN="${6:-quadpocadmin}"
TOPIC_NAME="${7:-quad-poc-bus}"

# Validation
if [ -z "$SUBSCRIPTION_ID" ]; then
    echo "Error: SubscriptionId is required"
    echo "Usage: ./deploy.sh <SubscriptionId> <SqlAdminPassword> [Location] [ResourceGroupName] [NamePrefix] [SqlAdminLogin] [TopicName]"
    exit 1
fi

if [ -z "$SQL_ADMIN_PASSWORD" ]; then
    echo "Error: SqlAdminPassword is required"
    echo "Usage: ./deploy.sh <SubscriptionId> <SqlAdminPassword> [Location] [ResourceGroupName] [NamePrefix] [SqlAdminLogin] [TopicName]"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TEMPLATE_FILE="$SCRIPT_DIR/../main.bicep"

# Get client IP address
echo "Getting client IP address..."
CLIENT_IP_ADDRESS=$(curl -s https://api.ipify.org?format=json | grep -o '"ip":"[^"]*' | cut -d'"' -f4)
echo "Client IP: $CLIENT_IP_ADDRESS"

# Set Azure subscription
echo "Setting Azure subscription..."
az account set --subscription "$SUBSCRIPTION_ID"

# Create deployment name with timestamp
DEPLOYMENT_NAME="quad-poc-$(date +%Y%m%d%H%M%S)"

echo "Starting deployment: $DEPLOYMENT_NAME"
echo "Location: $LOCATION"
echo "Resource Group: $RESOURCE_GROUP_NAME"
echo "Template: $TEMPLATE_FILE"

# Deploy
az deployment sub create \
  --name "$DEPLOYMENT_NAME" \
  --location "$LOCATION" \
  --template-file "$TEMPLATE_FILE" \
  --parameters \
      location="$LOCATION" \
      resourceGroupName="$RESOURCE_GROUP_NAME" \
      createResourceGroup=true \
      namePrefix="$NAME_PREFIX" \
      topicName="$TOPIC_NAME" \
      sqlAdminLogin="$SQL_ADMIN_LOGIN" \
      sqlAdminPassword="$SQL_ADMIN_PASSWORD" \
      clientIpAddress="$CLIENT_IP_ADDRESS"

echo ""
echo "Deployment complete!"
echo ""
echo "To view outputs, run:"
echo "az deployment sub show --name $DEPLOYMENT_NAME --query properties.outputs"
