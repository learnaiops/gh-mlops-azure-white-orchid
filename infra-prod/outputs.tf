output "resource_group_name" {
  description = "Prod resource group — set as prodResourceGroup in the Azure Pipelines variable group"
  value       = azurerm_resource_group.main.name
}

output "ml_workspace_name" {
  description = "Prod Azure ML workspace name — set as prodMlWorkspace in the Azure Pipelines variable group"
  value       = azurerm_machine_learning_workspace.main.name
}

output "ml_workspace_id" {
  value = azurerm_machine_learning_workspace.main.id
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "aks_resource_id" {
  value = azurerm_kubernetes_cluster.main.id
}

output "aks_compute_name" {
  description = "Kubernetes compute target name — set as prodComputeName in the Azure Pipelines variable group"
  value       = var.aks_compute_name
}

output "prod_endpoint_name" {
  description = "AKS online endpoint name — set as prodEndpointName in the Azure Pipelines variable group"
  value       = var.prod_endpoint_name
}

output "prod_deployment_name" {
  description = "AKS online deployment name — set as prodDeploymentName in the Azure Pipelines variable group"
  value       = var.prod_deployment_name
}

output "container_registry_login_server" {
  value = azurerm_container_registry.ml.login_server
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}

output "application_insights_connection_string" {
  value     = azurerm_application_insights.main.connection_string
  sensitive = true
}

output "application_insights_instrumentation_key" {
  value     = azurerm_application_insights.main.instrumentation_key
  sensitive = true
}

output "key_vault_uri" {
  value = azurerm_key_vault.ml.vault_uri
}

output "dashboard_url" {
  value = "https://portal.azure.com/#@/dashboard/arm${azurerm_portal_dashboard.main.id}"
}

output "post_deploy_instructions" {
  value = <<-EOT
    After the first model-promote pipeline run:

    1. Get the prod endpoint scoring URI:
         az ml online-endpoint show \
           --resource-group ${azurerm_resource_group.main.name} \
           --workspace-name ${azurerm_machine_learning_workspace.main.name} \
           --name ${var.prod_endpoint_name} \
           --query scoring_uri -o tsv

    2. Set it in the pre-prod Key Vault so the UI can call both endpoints:
         az keyvault secret set \
           --vault-name <preprod-kv-name> \
           --name prod-ml-endpoint-url \
           --value <scoring-uri>

         az keyvault secret set \
           --vault-name <preprod-kv-name> \
           --name prod-ml-endpoint-key \
           --value <prod-endpoint-primary-key>

    3. Re-run terraform apply on infra-prod/ to activate data collection
       and the white-orchid-risk-prod-monitor drift schedule.
  EOT
}
