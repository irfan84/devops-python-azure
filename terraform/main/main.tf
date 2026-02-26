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
resource "azurerm_service_plan" "plan" {
# checkov:skip=CKV_AZURE_212: Minimum instance count not required for portfolio environment
# checkov:skip=CKV_AZURE_225: Zone redundancy requires Premium SKU (cost optimization decision)
  
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
resource "azurerm_linux_web_app" "app" {
# checkov:skip=CKV_AZURE_13: App Service Authentication not required for public demo app
# checkov:skip=CKV_AZURE_17: Client certificate enforcement not required for demo
# checkov:skip=CKV_AZURE_222: Public network access required for public-facing portfolio app
# checkov:skip=CKV_AZURE_88: Azure Files not required for stateless demo app

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
    always_on           = true
    minimum_tls_version = "1.2"
    ftps_state          = "Disabled"
    health_check_path   = "/health"
    http2_enabled       = true

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
# 1. External Lookups
# --------------------

# Look up your manual Service Principal using its Client ID
data "azuread_service_principal" "pipeline_sp" {
  client_id = "b424d3e4-4de9-4831-98f2-defcea06e44f"
}

# Get configuration of the current authenticated user (You or the Pipeline)
data "azurerm_client_config" "current" {}

# --------------------
# 2. Key Vault Resource
# --------------------
resource "azurerm_key_vault" "kv" {
   # checkov:skip=CKV2_AZURE_32: Private endpoint not required for demo
  name                        = "kv-${local.name}-${random_string.suffix.result}"
  location                    = azurerm_resource_group.app.location
  resource_group_name         = azurerm_resource_group.app.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"

  purge_protection_enabled      = true
  soft_delete_retention_days    = 7
  public_network_access_enabled = true

  # --- Network Security Section ---
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  # --- Permission Model Section ---
  enable_rbac_authorization = true
}

# --------------------
# 3. RBAC Role Assignments
# --------------------

# Give the CURRENT USER (you or the runner) full admin rights to the vault
resource "azurerm_role_assignment" "tf_admin" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Give the MANUAL PIPELINE SP the ability to manage secrets
resource "azurerm_role_assignment" "pipeline_sp_access" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azuread_service_principal.pipeline_sp.object_id
}

# --------------------
# 4. Key Vault Secret
# --------------------
resource "azurerm_key_vault_secret" "app_secret" {
  name            = "APP-SECRET"
  value           = "change-me"
  key_vault_id    = azurerm_key_vault.kv.id
  content_type    = "text/plain"
  expiration_date = timeadd(timestamp(), "8760h")
  
  # Explicitly wait for permissions and network rules to settle
  depends_on = [
    azurerm_role_assignment.tf_admin,
    azurerm_role_assignment.pipeline_sp_access,
    azurerm_key_vault.kv
  ]
}