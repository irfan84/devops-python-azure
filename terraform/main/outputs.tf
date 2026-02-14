output "staging_url" {
  value = "${azurerm_linux_web_app.app.name}-staging.azurewebsites.net"
}

output "app_insights_name" {
  value = azurerm_application_insights.ai.name
}

output "log_analytics_workspace" {
  value = azurerm_log_analytics_workspace.law.name
}

output "key_vault_name" {
  value = azurerm_key_vault.kv.name
}
