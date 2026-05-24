resource "azurerm_storage_container" "data" {
  name                  = "data"
  storage_account_id    = azurerm_storage_account.ml.id
  container_access_type = "private"
}

# Seed the training CSV. Lifecycle ignores content changes so a pipeline re-upload
# (drift simulation) is not reverted by terraform apply.
resource "azurerm_storage_blob" "health_insurance_csv" {
  name                   = "health_insurance_risk/health_insurance_risk_dataset.csv"
  storage_account_name   = azurerm_storage_account.ml.name
  storage_container_name = azurerm_storage_container.data.name
  type                   = "Block"
  source                 = "${path.module}/../machinelearning/white-orchid/data/health_insurance_risk_dataset.csv"

  lifecycle {
    ignore_changes = [source, content_md5]
  }
}

# Register the container as an AML datastore via CLI (no native Terraform resource)
resource "null_resource" "health_insurance_datastore" {
  triggers = {
    workspace_id   = azurerm_machine_learning_workspace.main.id
    container_name = azurerm_storage_container.data.name
  }

  provisioner "local-exec" {
    command = <<-EOT
      cat > /tmp/health_insurance_datastore.yml << 'YAML'
      $schema: https://azuremlschemas.azureedge.net/latest/azureBlob.schema.json
      name: health_insurance_risk_dataset_data
      type: azure_blob
      account_name: ${azurerm_storage_account.ml.name}
      container_name: ${azurerm_storage_container.data.name}
      credentials:
        account_key: ${azurerm_storage_account.ml.primary_access_key}
      YAML

      az ml datastore create \
        --file /tmp/health_insurance_datastore.yml \
        --resource-group ${azurerm_resource_group.main.name} \
        --workspace-name ${azurerm_machine_learning_workspace.main.name}
    EOT
  }
}

# Allow the pipeline SPN to read/upload blobs (drift CSV re-uploads, WEBSITE_RUN_FROM_PACKAGE)
resource "azurerm_role_assignment" "spn_data_blob_contributor" {
  scope                = azurerm_storage_account.ml.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azuread_service_principal.service_connection.object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "spn_storage_key_operator" {
  scope                = azurerm_storage_account.ml.id
  role_definition_name = "Storage Account Key Operator Service Role"
  principal_id         = data.azuread_service_principal.service_connection.object_id
  principal_type       = "ServicePrincipal"
}
