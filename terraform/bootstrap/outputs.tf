output "backend_resource_group" {
  value = azurerm_resource_group.tfstate.name
}

output "backend_storage_account" {
  value = azurerm_storage_account.tfstate.name
}

output "backend_container" {
  value = azurerm_storage_container.tfstate.name
}
