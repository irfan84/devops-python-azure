locals {
  name = "${var.project}-${var.environment}"
}

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-tfstate-${local.name}"
  location = var.location
}

resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

# -------------------------------------------------
# Terraform State Storage Account (Enterprise Safe)
# -------------------------------------------------
## checkov:skip=CKV_AZURE_33: Queue logging not required for terraform backend
# checkov:skip=CKV2_AZURE_1: CMK encryption not required for portfolio backend
# checkov:skip=CKV2_AZURE_33: Private endpoint not required for demo environment
# checkov:skip=CKV2_AZURE_40: Shared key restriction not required for backend state
# checkov:skip=CKV2_AZURE_41: SAS expiration policy not required for backend
resource "azurerm_storage_account" "tfstate" {
  name                            = "tfstate${var.project}${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.tfstate.name
  location                        = azurerm_resource_group.tfstate.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"

  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = {
    environment = var.environment
    purpose     = "terraform-state"
  }
}

# -------------------------------------------------
# Storage Container
# -------------------------------------------------
resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}
