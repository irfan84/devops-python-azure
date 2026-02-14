#############################################
# main.tf (clean, enterprise-style)
# - App Service (Linux) + staging slot
# - Log Analytics + Application Insights (workspace-based)
# - App Insights wired to BOTH prod + staging
# - App Service diagnostic logs enabled
# - Key Vault (access policy model for simplicity)
# - Managed Identity enabled on Web App (future-ready)
#############################################

locals {
  name = "${var.project}-${var.environment}"
}

# --------------------
# Resource Group
# --------------------
resource "azurerm_resource_group" "app" {
  name     = "rg-${local.name}"
  location = var.location
}

# --------------------
# Random suffix for globally-unique resource names
# --------------------
resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

# --------------------
# App Service Plan (S1 supports deployment slots)
# --------------------
resource "azurerm_service_plan" "plan" {
  name                = "asp-${local.name}"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  os_type             = "Linux"
  sku_name            = "S1"
}

# --------------------
# Log Analytics Workspace
# --------------------
resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-${local.name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# --------------------
# Application Insights (workspace-based)
# --------------------
resource "azurerm_application_insights" "ai" {
  name                = "appi-${local.name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.law.id
}

# --------------------
# Linux Web App (Production slot)
# --------------------
resource "azurerm_linux_web_app" "app" {
  name                = "app-${local.name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  service_plan_id     = azurerm_service_plan.plan.id

  # Future-ready: enables Managed Identity (great for Key Vault integration later)
  identity {
    type = "SystemAssigned"
  }

  site_config {
  always_on = true

  application_stack {
    python_version = "3.10"
  }

  app_command_line = "gunicorn main:app --bind=0.0.0.0:8000"
}

  # Basic diagnostics: helpful for enterprise troubleshooting
  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }

  app_settings = {
    WEBSITES_PORT                  = "8000"
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"

    # App Insights (wire telemetry)
    APPINSIGHTS_INSTRUMENTATIONKEY        = azurerm_application_insights.ai.instrumentation_key
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.ai.connection_string
  }
}

# --------------------
# Staging Slot (monitored too)
# --------------------
resource "azurerm_linux_web_app_slot" "staging" {
  name           = "staging"
  app_service_id = azurerm_linux_web_app.app.id

  site_config {
    always_on = true

    application_stack {
      python_version = "3.10"
    }

    app_command_line = "gunicorn main:app --bind=0.0.0.0:8000"
  }

  app_settings = {
    WEBSITES_PORT = "8000"
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true" 

    # App Insights (wire telemetry for staging too)
    APPINSIGHTS_INSTRUMENTATIONKEY        = azurerm_application_insights.ai.instrumentation_key
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.ai.connection_string
  }
}

# --------------------
# Key Vault (Access Policy model for learning / simplicity)
# --------------------
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                       = "kv-${local.name}-${random_string.suffix.result}"
  location                   = azurerm_resource_group.app.location
  resource_group_name        = azurerm_resource_group.app.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"

  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  # Keep access policy model on for this project
  enable_rbac_authorization = false
}

# Key Vault Access Policy (Terraform identity/user)
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete"
  ]
}

# Key Vault Secret
resource "azurerm_key_vault_secret" "app_secret" {
  name         = "APP-SECRET"
  value        = "change-me"
  key_vault_id = azurerm_key_vault.kv.id

  # Avoid eventual-consistency / ordering issues
  depends_on = [
    azurerm_key_vault_access_policy.current_user
  ]
}
