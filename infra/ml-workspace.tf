data "azurerm_client_config" "current" {}

data "azuread_service_principal" "service_connection" {
  client_id = var.service_connection_client_id
}

resource "azurerm_storage_account" "ml" {
  name                     = replace("st${local.name_prefix}", "-", "")
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = local.common_tags
}

resource "azurerm_key_vault" "ml" {
  name                          = "kv-${local.name_prefix}"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  purge_protection_enabled      = false
  enable_rbac_authorization     = true
  tags                          = local.common_tags
}

# Terraform runner (whoever runs `terraform apply`) must be able to write secrets.
# Without this, `azurerm_key_vault_secret` resources will get a 403.
resource "azurerm_role_assignment" "terraform_kv_secrets_officer" {
  scope                = azurerm_key_vault.ml.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_container_registry" "ml" {
  name                = replace("acr${local.name_prefix}", "-", "")
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = true
  tags                = local.common_tags
}

resource "azurerm_machine_learning_workspace" "main" {
  name                          = "mlw-${local.name_prefix}"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  application_insights_id       = azurerm_application_insights.main.id
  key_vault_id                  = azurerm_key_vault.ml.id
  storage_account_id            = azurerm_storage_account.ml.id
  container_registry_id         = azurerm_container_registry.ml.id
  public_network_access_enabled = true

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# Compute cluster for training jobs
resource "azurerm_machine_learning_compute_cluster" "train" {
  name                          = "cpu-cluster"
  location                      = azurerm_resource_group.main.location
  machine_learning_workspace_id = azurerm_machine_learning_workspace.main.id
  vm_priority                   = "Dedicated"
  vm_size                       = "Standard_DS3_v2"

  scale_settings {
    min_node_count                       = 0
    max_node_count                       = 2
    scale_down_nodes_after_idle_duration = "PT2M"
  }

  identity {
    type = "SystemAssigned"
  }
}

# AzureML Data Scientist — allows job submission, model registration, endpoint operations
resource "azurerm_role_assignment" "spn_ml_data_scientist" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "AzureML Data Scientist"
  principal_id         = data.azuread_service_principal.service_connection.object_id
  principal_type       = "ServicePrincipal"
}

# Contributor on RG — required for endpoint provisioning (ARM writes)
resource "azurerm_role_assignment" "spn_contributor" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = data.azuread_service_principal.service_connection.object_id
  principal_type       = "ServicePrincipal"
}
