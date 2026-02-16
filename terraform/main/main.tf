#############################################
# main.tf (enterprise-hardened baseline)
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
# Random suffix
# --------------------
resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

# --------------------
# App Service Plan
# --------------------
# checkov:skip=CKV_AZURE_212: Minimum instances skipped for cost efficiency
# checkov:skip=CKV_AZURE_225: Zone redundancy skipped for cost efficiency
resource "azurerm_service_plan" "plan" {
  name                = "asp-${local.name}"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  os_type             = "Linux"
  sku_name            = "S1"
}

# --------------------
# Log Analytics
# --------------------
resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-${local.name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# --------------------
# Application Insights
# --------------------
resource "azurerm_application_insights" "ai" {
  name                = "appi-${local.name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.law.id
}

# --------------------
# Linux Web App (Production)
# --------------------
# checkov:skip=CKV_AZURE_13: App Service authentication not required for demo
# checkov:skip=CKV_AZURE_17: Client certificates not required for demo
# checkov:skip=CKV_AZURE_18: HTTP version policy not enforced for demo
# checkov:skip=CKV_AZURE_222: Public network access required for public web app
# checkov:skip=CKV_AZURE_88: Azure Files not required for this workload
resource "azurerm_linux_web_app" "app" {
  name                = "app-${local.name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  service_plan_id     = azurerm_service_plan.plan.id

  https_only = true
  client_affinity_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on            = true
    minimum_tls_version  = "1.2"
    ftps_state           = "Disabled"
    health_check_path    = "/health"

    application_stack {
      python_version = "3.10"
    }

    app_command_line = "gunicorn main:app --bind=0.0.0.0:8000"
  }

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

    APPINSIGHTS_INSTRUMENTATIONKEY        = azurerm_application_insights.ai.instrumentation_key
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.ai.connection_string
  }
}

# --------------------
# Staging Slot
# --------------------
resource "azurerm_linux_web_app_slot" "staging" {
  name           = "staging"
  app_service_id = azurerm_linux_web_app.app.id

  https_only = true

  site_config {
    always_on           = true
    minimum_tls_version = "1.2"
    ftps_state          = "Disabled"
    health_check_path   = "/health"

    application_stack {
      python_version = "3.10"
    }

    app_command_line = "gunicorn main:app --bind=0.0.0.0:8000"
  }

  app_settings = {
    WEBSITES_PORT                  = "8000"
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"

    APPINSIGHTS_INSTRUMENTATIONKEY        = azurerm_application_insights.ai.instrumentation_key
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.ai.connection_string
  }
}

# --------------------
# Key Vault
# --------------------
# checkov:skip=CKV_AZURE_189: Public access allowed for demo simplicity
# checkov:skip=CKV2_AZURE_32: Private endpoint not implemented in portfolio project
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                       = "kv-${local.name}-${random_string.suffix.result}"
  location                   = azurerm_resource_group.app.location
  resource_group_name        = azurerm_resource_group.app.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"

  purge_protection_enabled   = true
  soft_delete_retention_days = 90
  public_network_access_enabled = true

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  enable_rbac_authorization = false
}

# --------------------
# KV Access Policy
# --------------------
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

# --------------------
# KV Secret
# --------------------
resource "azurerm_key_vault_secret" "app_secret" {
  name            = "APP-SECRET"
  value           = "change-me"
  key_vault_id    = azurerm_key_vault.kv.id
  content_type    = "text/plain"
  expiration_date = timeadd(timestamp(), "8760h")

  depends_on = [
    azurerm_key_vault_access_policy.current_user
  ]
}
