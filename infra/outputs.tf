output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "ml_workspace_name" {
  value = azurerm_machine_learning_workspace.main.name
}

output "storage_account_name" {
  value = azurerm_storage_account.ml.name
}

output "app_insights_connection_string" {
  value     = azurerm_application_insights.main.connection_string
  sensitive = true
}

output "app_insights_instrumentation_key" {
  value     = azurerm_application_insights.main.instrumentation_key
  sensitive = true
}

output "web_app_url" {
  value = "https://${azurerm_linux_web_app.ui.default_hostname}"
}

output "web_app_name" {
  value = azurerm_linux_web_app.ui.name
}

output "ml_endpoint_url" {
  value = "https://ep-${local.name_prefix}.swedencentral.inference.ml.azure.com/score"
}

output "key_vault_name" {
  value = azurerm_key_vault.ml.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.ml.vault_uri
}

output "web_app_principal_id" {
  description = "Object ID of the web app's system-assigned managed identity — used in KV role assignment"
  value       = azurerm_linux_web_app.ui.identity[0].principal_id
}

output "post_deploy_instructions" {
  value = <<-EOT
    After the first pipeline run, set the endpoint key in Key Vault:
      az keyvault secret set \
        --vault-name ${azurerm_key_vault.ml.name} \
        --name ml-endpoint-key \
        --value <scoring-key-from-azure-ml>
  EOT
}
