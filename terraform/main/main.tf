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
# App Service Plan (S1 supports slots)
# --------------------
resource "azurerm_service_plan" "plan" {
  name                = "asp-${local.name}"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  os_type             = "Linux"
  sku_name            = "S1"
}

# --------------------
# Random suffix for globally-unique names
# --------------------
resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

# --------------------
# Linux Web App
# --------------------
resource "azurerm_linux_web_app" "app" {
  name                = "app-${local.name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  service_plan_id     = azurerm_service_plan.plan.id

  site_config {
    always_on = true
    application_stack {
      python_version = "3.10"
    }
  }

  app_settings = {
    WEBSITES_PORT                 = "8000"
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
  }
}

# --------------------
# Staging Slot
# --------------------
resource "azurerm_linux_web_app_slot" "staging" {
  name           = "staging"
  app_service_id = azurerm_linux_web_app.app.id

  site_config {
    always_on = true
    application_stack {
      python_version = "3.10"
    }
  }

  app_settings = {
    WEBSITES_PORT = "8000"
  }
}

# --------------------
# Key Vault
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

  # Explicitly use access policies (simpler for learning)
  enable_rbac_authorization = false
}

# --------------------
# Key Vault Access Policy (for Terraform identity)
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
# Key Vault Secret
# --------------------
resource "azurerm_key_vault_secret" "app_secret" {
  name         = "APP-SECRET"
  value        = "change-me"
  key_vault_id = azurerm_key_vault.kv.id

  # Prevent race condition
  depends_on = [
    azurerm_key_vault_access_policy.current_user
  ]
}
