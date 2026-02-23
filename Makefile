# AzureApp PoC Makefile
# Manages development environment and testing

# Load environment variables from .env file
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

# Configuration
FUNCTION_URL ?= https://quadpoc-func-jl7ui3o6bihgu.azurewebsites.net
SQL_SERVER ?= quadpoc-sql-jl7ui3o6bihgu.database.windows.net
SQL_DB ?= quadpoc-db
SQL_USER ?= quadpocadmin
SQL_PASSWORD ?= GRAPE123\#
RESOURCE_GROUP ?= rg-quad-poc-dev
NAMESPACE ?= quadpoc-sb-jl7ui3o6bihgu
TOPIC ?= quad-poc-bus
FUNCTION_APP ?= quadpoc-func-jl7ui3o6bihgu

# .NET Configuration
DOTNET_ROOT := /opt/homebrew/opt/dotnet@8/libexec
DOTNET_PATH := /opt/homebrew/opt/dotnet@8/bin
export PATH := $(DOTNET_PATH):$(PATH)
export DOTNET_ENVIRONMENT := Development
export ASPNETCORE_ENVIRONMENT := Development

.PHONY: help
help: ## Show this help message
	@echo "\033[0;34mAzureApp PoC - Available Commands\033[0m"
	@echo ""
	@grep -h -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sort | while IFS=':' read -r target rest; do \
		desc=$$(echo "$$rest" | sed 's/.*## //'); \
		printf "  \033[0;32m%-20s\033[0m %s\n" "$$target" "$$desc"; \
	done
	@echo ""

.PHONY: worker
worker: ## Start the Worker to process Service Bus messages
	@echo "\033[0;32mStarting Worker...\033[0m"
	@if [ -f .env ]; then \
		echo "Loading environment variables from .env..."; \
		export $$(grep -v '^#' .env | xargs); \
	fi
	@cd src/Quad.Poc.Worker && dotnet run

.PHONY: worker-bg
worker-bg: ## Start Worker in background
	@echo "\033[0;32mStarting Worker in background...\033[0m"
	@if [ -f .env ]; then \
		export $$(grep -v '^#' .env | xargs); \
	fi; \
	cd src/Quad.Poc.Worker && dotnet run > ../../worker.log 2>&1 & echo $$! > ../../worker.pid
	@echo "Worker PID: $$(cat worker.pid)"
	@echo "Logs: tail -f worker.log"

.PHONY: worker-stop
worker-stop: ## Stop background Worker
	@if [ -f worker.pid ]; then \
		echo "\033[0;33mStopping Worker (PID: $$(cat worker.pid))...\033[0m"; \
		kill $$(cat worker.pid) 2>/dev/null || true; \
		rm worker.pid; \
		echo "\033[0;32mWorker stopped\033[0m"; \
	else \
		echo "\033[0;31mNo worker.pid file found\033[0m"; \
	fi

.PHONY: worker-logs
worker-logs: ## Show Worker logs (if running in background)
	@tail -f worker.log

.PHONY: status
status: ## Check status of database and Service Bus
	@echo "\033[0;34mChecking Azure Resources Status...\033[0m"
	@echo ""
	@echo "\033[0;33m=== Database Operations ===$(NC)"
	@sqlcmd -S $(SQL_SERVER) -d $(SQL_DB) -U $(SQL_USER) -P "$(SQL_PASSWORD)" -h -1 \
		-Q "SELECT COUNT(*) as total, status FROM operations GROUP BY status;" 2>/dev/null || echo "Could not connect to database"
	@echo ""
	@echo "\033[0;33m=== Resource Snapshots ===$(NC)"
	@sqlcmd -S $(SQL_SERVER) -d $(SQL_DB) -U $(SQL_USER) -P "$(SQL_PASSWORD)" -h -1 \
		-Q "SELECT COUNT(*) as total FROM resource_snapshots;" 2>/dev/null || echo "Could not connect to database"
	@echo ""
	@echo "\033[0;33m=== Service Bus Message Counts ===$(NC)"
	@az servicebus topic subscription show \
		--resource-group $(RESOURCE_GROUP) \
		--namespace-name $(NAMESPACE) \
		--topic-name $(TOPIC) \
		--name commands \
		--query "countDetails" \
		--output table 2>/dev/null || echo "Could not connect to Service Bus"
	@echo ""

.PHONY: test
test: ## Run quick test suite
	@echo "\033[0;32mRunning test suite...\033[0m"
	@echo ""
	@TIMESTAMP=$$(date +%s); \
	ITEM_ID="test-$$TIMESTAMP"; \
	IDEM_KEY="key-$$TIMESTAMP"; \
	echo "\033[0;34m=== Creating test item: $$ITEM_ID ===\033[0m"; \
	RESPONSE=$$(curl -s -X PUT "$(FUNCTION_URL)/v1/items/$$ITEM_ID" \
		-H "Content-Type: application/json" \
		-H "Idempotency-Key: $$IDEM_KEY" \
		-d '{"name": "Test Item", "value": 42}'); \
	echo "$$RESPONSE" | jq .; \
	OPERATION_ID=$$(echo "$$RESPONSE" | jq -r '.OperationId'); \
	echo ""; \
	echo "\033[0;34m=== Checking operation status ===\033[0m"; \
	for i in 1 2 3 4 5; do \
		sleep 2; \
		STATUS=$$(curl -s "$(FUNCTION_URL)/v1/operations/$$OPERATION_ID"); \
		echo "Attempt $$i:"; \
		echo "$$STATUS" | jq .; \
		if echo "$$STATUS" | jq -e '.Status == "succeeded"' > /dev/null; then \
			echo ""; \
			echo "\033[0;32m✓ Operation succeeded!\033[0m"; \
			break; \
		fi; \
	done; \
	echo ""; \
	echo "\033[0;34m=== Getting item ===\033[0m"; \
	curl -s "$(FUNCTION_URL)/v1/items/$$ITEM_ID" | jq .

.PHONY: test-simple
test-simple: ## Create a simple test item
	@echo "\033[0;32mCreating test item...\033[0m"
	@curl -X PUT "$(FUNCTION_URL)/v1/items/test-$$(date +%s)" \
		-H "Content-Type: application/json" \
		-H "Idempotency-Key: key-$$(date +%s)" \
		-d '{"name": "Test Item", "value": 42}' | jq

.PHONY: deploy
deploy: ## Deploy Function App to Azure
	@echo "\033[0;32mDeploying Function App to Azure...\033[0m"
	@cd src/Quad.Poc.Functions && func azure functionapp publish $(FUNCTION_APP)

.PHONY: deploy-infra
deploy-infra: ## Deploy Azure infrastructure (requires SUBSCRIPTION_ID and SQL_PASSWORD)
	@if [ -z "$(SUBSCRIPTION_ID)" ]; then \
		echo "\033[0;31mError: SUBSCRIPTION_ID not set\033[0m"; \
		echo "Usage: make deploy-infra SUBSCRIPTION_ID=<id> SQL_PASSWORD=<password>"; \
		exit 1; \
	fi
	@if [ -z "$(SQL_PASSWORD)" ]; then \
		echo "\033[0;31mError: SQL_PASSWORD not set\033[0m"; \
		echo "Usage: make deploy-infra SUBSCRIPTION_ID=<id> SQL_PASSWORD=<password>"; \
		exit 1; \
	fi
	@echo "\033[0;32mDeploying Azure infrastructure...\033[0m"
	@LOCATION="centralus"; \
	RESOURCE_GROUP_NAME="rg-quad-poc-dev"; \
	NAME_PREFIX="quadpoc"; \
	SQL_ADMIN_LOGIN="quadpocadmin"; \
	TOPIC_NAME="quad-poc-bus"; \
	TEMPLATE_FILE="./infra/main.bicep"; \
	echo "Getting client IP address..."; \
	CLIENT_IP=$$(curl -s https://api.ipify.org?format=json | jq -r '.ip'); \
	echo "Client IP: $$CLIENT_IP"; \
	echo "Setting Azure subscription..."; \
	az account set --subscription "$(SUBSCRIPTION_ID)"; \
	DEPLOYMENT_NAME="quad-poc-$$(date +%Y%m%d%H%M%S)"; \
	echo "Starting deployment: $$DEPLOYMENT_NAME"; \
	echo "Location: $$LOCATION"; \
	echo "Resource Group: $$RESOURCE_GROUP_NAME"; \
	az deployment sub create \
		--name "$$DEPLOYMENT_NAME" \
		--location "$$LOCATION" \
		--template-file "$$TEMPLATE_FILE" \
		--parameters \
			location="$$LOCATION" \
			resourceGroupName="$$RESOURCE_GROUP_NAME" \
			createResourceGroup=true \
			namePrefix="$$NAME_PREFIX" \
			topicName="$$TOPIC_NAME" \
			sqlAdminLogin="$$SQL_ADMIN_LOGIN" \
			sqlAdminPassword="$(SQL_PASSWORD)" \
			clientIpAddress="$$CLIENT_IP"; \
	echo ""; \
	echo "\033[0;32mDeployment complete!\033[0m"

.PHONY: delete-infra
delete-infra: ## Delete all Azure infrastructure (stops all charges)
	@echo "\033[0;33m⚠️  WARNING: This will delete ALL Azure resources in $(RESOURCE_GROUP)\033[0m"
	@echo ""
	@read -p "Are you sure? Type 'yes' to confirm: " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		echo "\033[0;32mDeleting resource group $(RESOURCE_GROUP)...\033[0m"; \
		az group delete --name $(RESOURCE_GROUP) --yes --no-wait; \
		echo ""; \
		echo "\033[0;32m✓ Deletion initiated (will complete in background)\033[0m"; \
		echo "Run 'make list-resources' to check if deletion is complete"; \
	else \
		echo "\033[0;33mDeletion cancelled\033[0m"; \
	fi

.PHONY: delete-infra-force
delete-infra-force: ## Delete all Azure infrastructure WITHOUT confirmation (USE WITH CAUTION)
	@echo "\033[0;31mDeleting resource group $(RESOURCE_GROUP) without confirmation...\033[0m"
	@az group delete --name $(RESOURCE_GROUP) --yes --no-wait
	@echo ""
	@echo "\033[0;32m✓ Deletion initiated (will complete in background)\033[0m"
	@echo "Run 'make list-resources' to check if deletion is complete"

.PHONY: list-resources
list-resources: ## List all Azure resources in resource group
	@echo "\033[0;34mAzure Resources in $(RESOURCE_GROUP):\033[0m"
	@echo ""
	@az resource list --resource-group $(RESOURCE_GROUP) --output table 2>/dev/null || echo "Resource group not found or no resources"

.PHONY: stop-function
stop-function: ## Stop Function App (reduces costs but keeps infrastructure)
	@echo "\033[0;32mStopping Function App $(FUNCTION_APP)...\033[0m"
	@az functionapp stop --name $(FUNCTION_APP) --resource-group $(RESOURCE_GROUP)
	@echo "\033[0;32m✓ Function App stopped\033[0m"

.PHONY: start-function
start-function: ## Start Function App
	@echo "\033[0;32mStarting Function App $(FUNCTION_APP)...\033[0m"
	@az functionapp start --name $(FUNCTION_APP) --resource-group $(RESOURCE_GROUP)
	@echo "\033[0;32m✓ Function App started\033[0m"

.PHONY: db-operations
db-operations: ## View all operations in database
	@echo "\033[0;34mDatabase Operations:\033[0m"
	@sqlcmd -S $(SQL_SERVER) -d $(SQL_DB) -U $(SQL_USER) -P "$(SQL_PASSWORD)" -h -1 \
		-Q "SELECT TOP 10 CONVERT(VARCHAR(36), operationId) as operationId, status, resourceId, CONVERT(VARCHAR(19), createdAt, 120) as created FROM operations ORDER BY createdAt DESC;"

.PHONY: db-snapshots
db-snapshots: ## View all resource snapshots in database
	@echo "\033[0;34mResource Snapshots:\033[0m"
	@sqlcmd -S $(SQL_SERVER) -d $(SQL_DB) -U $(SQL_USER) -P "$(SQL_PASSWORD)" -h -1 \
		-Q "SELECT resourceType, resourceId, CONVERT(VARCHAR(19), updatedAt, 120) as updated FROM resource_snapshots ORDER BY updatedAt DESC;"

.PHONY: db-clean
db-clean: ## Clean all data from database tables
	@echo "\033[0;33mCleaning database tables...\033[0m"
	@sqlcmd -S $(SQL_SERVER) -d $(SQL_DB) -U $(SQL_USER) -P "$(SQL_PASSWORD)" \
		-Q "DELETE FROM resource_snapshots; DELETE FROM operations;"
	@echo "\033[0;32mDatabase cleaned\033[0m"

.PHONY: servicebus-status
servicebus-status: ## Check Service Bus message counts
	@echo "\033[0;34mService Bus Status:\033[0m"
	@echo ""
	@echo "Commands Subscription:"
	@az servicebus topic subscription show \
		--resource-group $(RESOURCE_GROUP) \
		--namespace-name $(NAMESPACE) \
		--topic-name $(TOPIC) \
		--name commands \
		--query "countDetails" \
		--output table
	@echo ""
	@echo "Results Subscription:"
	@az servicebus topic subscription show \
		--resource-group $(RESOURCE_GROUP) \
		--namespace-name $(NAMESPACE) \
		--topic-name $(TOPIC) \
		--name results \
		--query "countDetails" \
		--output table

.PHONY: logs
logs: ## Stream Function App logs from Azure
	@echo "\033[0;32mStreaming Azure Function App logs...\033[0m"
	@func azure functionapp logstream $(FUNCTION_APP)

.PHONY: clean
clean: ## Clean build artifacts
	@echo "\033[0;33mCleaning build artifacts...\033[0m"
	@find . -type d -name "bin" -o -name "obj" | xargs rm -rf
	@rm -f worker.log worker.pid
	@echo "\033[0;32mClean complete\033[0m"

.PHONY: build
build: ## Build all projects
	@echo "\033[0;32mBuilding Function App...\033[0m"
	@cd src/Quad.Poc.Functions && dotnet build
	@echo ""
	@echo "\033[0;32mBuilding Worker...\033[0m"
	@cd src/Quad.Poc.Worker && dotnet build
	@echo ""
	@echo "\033[0;32mBuild complete\033[0m"

.PHONY: restore
restore: ## Restore NuGet packages
	@echo "\033[0;32mRestoring packages...\033[0m"
	@dotnet restore

.PHONY: setup-env
setup-env: ## Create .env file from .env.example
	@if [ -f .env ]; then \
		echo "\033[0;33m.env file already exists\033[0m"; \
	else \
		cp .env.example .env; \
		echo "\033[0;32mCreated .env file from .env.example\033[0m"; \
		echo "\033[0;33mPlease edit .env with your configuration\033[0m"; \
	fi

.PHONY: install
install: ## Install required tools (homebrew, dotnet, az cli, sqlcmd)
	@echo "\033[0;32mInstalling required tools...\033[0m"
	@command -v brew >/dev/null 2>&1 || { echo "\033[0;31mHomebrew not installed. Install from https://brew.sh\033[0m"; exit 1; }
	@brew install dotnet@8 azure-cli sqlcmd
	@npm install -g azure-functions-core-tools@4 azurite
	@echo "\033[0;32mInstallation complete\033[0m"

.PHONY: dev
dev: ## Start complete development environment (Worker + logs)
	@echo "\033[0;32mStarting development environment...\033[0m"
	@$(MAKE) worker

.PHONY: watch
watch: ## Watch status in real-time
	@watch -n 3 make status

.PHONY: curl-examples
curl-examples: ## Show curl command examples
	@echo "\033[0;34mcURL Examples:\033[0m"
	@echo ""
	@echo "\033[0;32mCreate an item:\033[0m"
	@echo "  curl -X PUT \"$(FUNCTION_URL)/v1/items/my-item\" \\"
	@echo "    -H \"Content-Type: application/json\" \\"
	@echo "    -H \"Idempotency-Key: my-key-123\" \\"
	@echo "    -d '{\"name\": \"My Item\", \"value\": 100}' | jq"
	@echo ""
	@echo "\033[0;32mGet operation status:\033[0m"
	@echo "  curl \"$(FUNCTION_URL)/v1/operations/OPERATION_ID\" | jq"
	@echo ""
	@echo "\033[0;32mGet item:\033[0m"
	@echo "  curl \"$(FUNCTION_URL)/v1/items/my-item\" | jq"
	@echo ""

.PHONY: all
all: restore build ## Restore packages and build all projects

.DEFAULT_GOAL := help
