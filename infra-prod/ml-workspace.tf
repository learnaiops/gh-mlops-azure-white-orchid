data "azurerm_client_config" "current" {}

resource "azurerm_storage_account" "ml" {
  name                     = replace("st${local.name_prefix}", "-", "")
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
  tags                     = local.common_tags
}

resource "azurerm_key_vault" "ml" {
  name                       = "kv-prod-${random_string.suffix.result}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = true
  soft_delete_retention_days = 90
  tags                       = local.common_tags
}

resource "azurerm_container_registry" "ml" {
  name                = replace("acr${local.name_prefix}", "-", "")
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"
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
