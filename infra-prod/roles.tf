data "azurerm_subscription" "current" {}

data "azuread_service_principal" "service_connection" {
  client_id = var.service_connection_client_id
}

# AKS kubelet identity → AcrPull on the prod ACR so nodes can pull inference images
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.ml.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

# ML workspace MSI → Contributor on the prod ACR so AML can build and push environments
resource "azurerm_role_assignment" "mlw_acr_contributor" {
  scope                = azurerm_container_registry.ml.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_machine_learning_workspace.main.identity[0].principal_id
}

# ML workspace MSI → AKS RBAC Cluster Admin so AML can manage inference workloads on the cluster
resource "azurerm_role_assignment" "mlw_aks_admin" {
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = azurerm_machine_learning_workspace.main.identity[0].principal_id
}

# Service connection SPN → AzureML Data Scientist on the prod resource group
# (required for the pipeline to create/update online endpoints and deployments)
resource "azurerm_role_assignment" "spn_ml_data_scientist" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "AzureML Data Scientist"
  principal_id         = data.azuread_service_principal.service_connection.object_id
  principal_type       = "ServicePrincipal"
}

# Service connection SPN → Contributor on the prod resource group
# (required for ARM writes during endpoint provisioning)
resource "azurerm_role_assignment" "spn_contributor" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = data.azuread_service_principal.service_connection.object_id
  principal_type       = "ServicePrincipal"
}

# Service connection SPN → AKS Cluster User so the pipeline can get cluster credentials
resource "azurerm_role_assignment" "spn_aks_user" {
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = data.azuread_service_principal.service_connection.object_id
  principal_type       = "ServicePrincipal"
}

# ML workspace MSI → Storage Blob Data Contributor on the storage account
# (required for data collection: AML writes scored inputs/outputs to blob)
resource "azurerm_role_assignment" "mlw_storage_blob" {
  scope                = azurerm_storage_account.ml.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_machine_learning_workspace.main.identity[0].principal_id
}
