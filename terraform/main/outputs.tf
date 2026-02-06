output "resource_group" {
  value = azurerm_resource_group.app.name
}

output "web_app_name" {
  value = azurerm_linux_web_app.app.name
}

output "web_app_url" {
  value = azurerm_linux_web_app.app.default_hostname
}

output "key_vault_name" {
  value = azurerm_key_vault.kv.name
}
