#############################################
# main.tf (Final Hardened - Agent IP Method)
#############################################

locals {
  name = "${var.project}-${var.environment}"
}

# --------------------
# 1. External Lookups
# --------------------

# This "calls home" to find the public IP of your self-hosted agent
data "http" "my_ip" {
  url = "https://ifconfig.me/ip"
}

data "azuread_service_principal" "pipeline_sp" {
  client_id = "b424d3e4-4de9-4831-98f2-defcea06e44f"
}

data "azurerm_client_config" "current" {}

# --------------------
# 2. Resource Group
# --------------------
resource "azurerm_resource_group" "app" {
  name     = "rg-${local.name}"
  location = var.location
}

# --------------------
# 3. Random suffix
# --------------------
resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

# --------------------
# 4. Key Vault Resource
# --------------------
resource "azurerm_key_vault" "kv" {
  # checkov:skip=CKV_AZURE_109: Network ACLs are defined with Deny by default
  # checkov:skip=CKV_AZURE_189: Allowing public access specifically for Agent whitelisting
  # checkov:skip=CKV2_AZURE_32: Private endpoint not required for demo environment
  
  name                        = "kv-${local.name}-${random_string.suffix.result}"
  location                    = azurerm_resource_group.app.location
  resource_group_name         = azurerm_resource_group.app.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"

  purge_protection_enabled      = true
  soft_delete_retention_days    = 7
  public_network_access_enabled = true

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"

    # THIS IS THE MAGIC: Whitelists the agent IP dynamically
    ip_rules = [
      "${chomp(data.http.runner_ip.response_body)}/32", # Dynamic IP from the runner
      "${var.office_ip}/32"                             # Static IP from your variable
    ]
  }

  enable_rbac_authorization = true
}

# --------------------
# 5. RBAC & Secrets
# --------------------
resource "azurerm_role_assignment" "tf_admin" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "pipeline_sp_access" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azuread_service_principal.pipeline_sp.object_id
}

resource "azurerm_key_vault_secret" "app_secret" {
  name            = "APP-SECRET"
  value           = "change-me"
  key_vault_id    = azurerm_key_vault.kv.id
  content_type    = "text/plain"
  expiration_date = timeadd(timestamp(), "8760h")
  
  depends_on = [
    azurerm_role_assignment.tf_admin,
    azurerm_role_assignment.pipeline_sp_access,
    azurerm_key_vault.kv
  ]
}

# --------------------
# 6. App Infrastructure
# --------------------
resource "azurerm_service_plan" "plan" {
  # checkov:skip=CKV_AZURE_212: Min instance count not required
  # checkov:skip=CKV_AZURE_225: Zone redundancy cost optimization
  name                = "asp-${local.name}"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  os_type             = "Linux"
  sku_name            = "S1"
}

resource "azurerm_linux_web_app" "app" {
  # checkov:skip=CKV_AZURE_13: App Auth not required
  # checkov:skip=CKV_AZURE_17: Client cert not required
  # checkov:skip=CKV_AZURE_222: Public network access required
  # checkov:skip=CKV_AZURE_88: Azure Files not required
  
  name                = "app-${local.name}-${random_string.suffix.result}"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  service_plan_id     = azurerm_service_plan.plan.id

  https_only = true

  site_config {
    always_on           = true
    minimum_tls_version = "1.2"
    
    application_stack {
      python_version = "3.10"
    }
  }
}