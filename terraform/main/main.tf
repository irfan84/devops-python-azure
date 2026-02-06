locals {
  name = "${var.project}-${var.environment}"
}

resource "azurerm_resource_group" "app" {
  name     = "rg-${local.name}"
  location = var.location
}

resource "azurerm_service_plan" "plan" {
  name                = "asp-${local.name}"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  os_type             = "Linux"
  sku_name            = "B1"
}

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
    WEBSITES_PORT                    = "8000"
    SCM_DO_BUILD_DURING_DEPLOYMENT    = "true"
  }
}

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

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

resource "azurerm_key_vault" "kv" {
  name                       = "kv-${local.name}-${random_string.suffix.result}"
  location                   = azurerm_resource_group.app.location
  resource_group_name        = azurerm_resource_group.app.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault_secret" "app_secret" {
  name         = "APP-SECRET"
  value        = "change-me"
  key_vault_id = azurerm_key_vault.kv.id
}
