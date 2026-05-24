resource "azurerm_service_plan" "main" {
  name                = "asp-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.app_service_sku
  tags                = local.common_tags
}

resource "azurerm_linux_web_app" "ui" {
  name                = "app-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id

  # System-assigned MI is used to pull secrets from Key Vault at runtime.
  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      node_version = "20-lts"
    }
    always_on        = false
    app_command_line = "node server.js"
  }

  app_settings = {
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    WEBSITE_NODE_DEFAULT_VERSION   = "~20"

    # Non-secret — stored as plain value
    ML_ENDPOINT_URL = "https://ep-${local.name_prefix}.swedencentral.inference.ml.azure.com/score"

    # Secrets — resolved from Key Vault at runtime via the web app's managed identity.
    # No secret value ever lives in Terraform state or App Service config as plaintext.
    ML_ENDPOINT_KEY = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.ml_endpoint_key.versionless_id})"

    APPLICATIONINSIGHTS_CONNECTION_STRING = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.appinsights_connection_string.versionless_id})"
    APPINSIGHTS_INSTRUMENTATIONKEY        = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.appinsights_instrumentation_key.versionless_id})"
  }

  tags = local.common_tags
}

# ── Key Vault secrets ─────────────────────────────────────────────────────────

# ML endpoint key — initially a placeholder; update manually in KV after first pipeline run.
# lifecycle.ignore_changes prevents terraform apply from reverting a manual update.
resource "azurerm_key_vault_secret" "ml_endpoint_key" {
  name         = "ml-endpoint-key"
  value        = var.ml_endpoint_key != "" ? var.ml_endpoint_key : "NOT_YET_SET"
  key_vault_id = azurerm_key_vault.ml.id

  lifecycle {
    ignore_changes = [value]
  }

  depends_on = [azurerm_role_assignment.terraform_kv_secrets_officer]
}

resource "azurerm_key_vault_secret" "appinsights_connection_string" {
  name         = "appinsights-connection-string"
  value        = azurerm_application_insights.main.connection_string
  key_vault_id = azurerm_key_vault.ml.id

  depends_on = [azurerm_role_assignment.terraform_kv_secrets_officer]
}

resource "azurerm_key_vault_secret" "appinsights_instrumentation_key" {
  name         = "appinsights-instrumentation-key"
  value        = azurerm_application_insights.main.instrumentation_key
  key_vault_id = azurerm_key_vault.ml.id

  depends_on = [azurerm_role_assignment.terraform_kv_secrets_officer]
}

# ── Role assignments ──────────────────────────────────────────────────────────

# Web app MI reads KV secrets (resolves the @Microsoft.KeyVault(...) references above)
resource "azurerm_role_assignment" "webapp_kv_secrets_user" {
  scope                = azurerm_key_vault.ml.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.ui.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# Pipeline SPN deploys the built UI to the web app
resource "azurerm_role_assignment" "spn_webapp_contributor" {
  scope                = azurerm_linux_web_app.ui.id
  role_definition_name = "Website Contributor"
  principal_id         = data.azuread_service_principal.service_connection.object_id
  principal_type       = "ServicePrincipal"
}
