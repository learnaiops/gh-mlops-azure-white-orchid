resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  dns_prefix          = "${var.project}-prod"
  sku_tier            = "Standard"

  default_node_pool {
    name                        = "system"
    vm_size                     = var.aks_node_vm_size
    min_count                   = var.aks_min_node_count
    max_count                   = var.aks_max_node_count
    auto_scaling_enabled        = true
    vnet_subnet_id              = azurerm_subnet.aks.id
    temporary_name_for_rotation = "systmp"

    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    service_cidr   = "10.3.0.0/16"
    dns_service_ip = "10.3.0.10"
  }

  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.main.id
    msi_auth_for_monitoring_enabled = true
  }

  azure_policy_enabled = true

  tags = local.common_tags
}

# Install the Azure ML Kubernetes extension on the AKS cluster.
# Sets up the inference router (LoadBalancer) and wires up the AML agent
# that handles scoring request routing from the online endpoint.
resource "null_resource" "aml_extension" {
  triggers = {
    aks_id = azurerm_kubernetes_cluster.main.id
  }

  provisioner "local-exec" {
    environment = {
      RG       = azurerm_resource_group.main.name
      AKS_NAME = azurerm_kubernetes_cluster.main.name
    }
    command = <<-EOT
      set -e
      az extension add --name k8s-extension --upgrade --yes 2>/dev/null || true

      EXTENSION_STATE=$(az k8s-extension show \
        --resource-group "$RG" \
        --cluster-name "$AKS_NAME" \
        --cluster-type managedClusters \
        --name aml-extension \
        --query provisioningState -o tsv 2>/dev/null || echo "NotFound")

      if [ "$EXTENSION_STATE" = "Succeeded" ]; then
        echo "AML extension already installed."
      else
        # Wait for AKS internal extension bridge to be ready before installing.
        echo "Waiting 120s for AKS extension bridge to initialize..."
        sleep 120

        INSTALL_ATTEMPT=0
        INSTALL_MAX=3
        until [ "$INSTALL_ATTEMPT" -ge "$INSTALL_MAX" ]; do
          INSTALL_ATTEMPT=$((INSTALL_ATTEMPT + 1))
          echo "AML extension install attempt $${INSTALL_ATTEMPT}/$${INSTALL_MAX}..."
          az k8s-extension create \
            --resource-group "$RG" \
            --cluster-name "$AKS_NAME" \
            --cluster-type managedClusters \
            --name aml-extension \
            --extension-type Microsoft.AzureML.Kubernetes \
            --config enableTraining=false \
                    enableInference=true \
                    inferenceRouterServiceType=LoadBalancer \
                    allowInsecureConnections=true \
                    inferenceLoadBalancerHA=false \
            --auto-upgrade-minor-version true && break
          echo "Install attempt $${INSTALL_ATTEMPT} failed; retrying in 60s..."
          sleep 60
        done

        MAX_WAIT=600
        ELAPSED=0
        while true; do
          STATE=$(az k8s-extension show \
            --resource-group "$RG" \
            --cluster-name "$AKS_NAME" \
            --cluster-type managedClusters \
            --name aml-extension \
            --query provisioningState -o tsv 2>/dev/null || echo "Unknown")
          echo "AML extension state: $STATE ($${ELAPSED}s elapsed)"
          [ "$STATE" = "Succeeded" ] && { echo "Extension ready."; break; }
          [ "$STATE" = "Failed" ]    && { echo "##[error] AML extension installation failed."; exit 1; }
          [ "$ELAPSED" -ge "$MAX_WAIT" ] && { echo "##[error] Timed out waiting for AML extension."; exit 1; }
          sleep 30
          ELAPSED=$((ELAPSED + 30))
        done
      fi
    EOT
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}

# Attach the AKS cluster to the Azure ML workspace as a Kubernetes compute target.
# After this step the workspace can create Kubernetes online endpoints that route
# traffic through the AML inference router running on the AKS cluster.
resource "null_resource" "aml_compute_attach" {
  triggers = {
    aks_id       = azurerm_kubernetes_cluster.main.id
    workspace_id = azurerm_machine_learning_workspace.main.id
  }

  provisioner "local-exec" {
    environment = {
      MLW_RG   = azurerm_resource_group.main.name
      MLW_NAME = azurerm_machine_learning_workspace.main.name
      COMPUTE  = var.aks_compute_name
      AKS_ID   = azurerm_kubernetes_cluster.main.id
    }
    command = <<-EOT
      set -e
      az extension add --name ml --upgrade --yes 2>/dev/null || true

      COMPUTE_STATE=$(az ml compute show \
        --resource-group "$MLW_RG" \
        --workspace-name "$MLW_NAME" \
        --name "$COMPUTE" \
        --query provisioningState -o tsv 2>/dev/null || echo "NotFound")

      if [ "$COMPUTE_STATE" = "Succeeded" ]; then
        echo "Kubernetes compute target '$COMPUTE' already attached."
      else
        az ml compute attach \
          --resource-group "$MLW_RG" \
          --workspace-name "$MLW_NAME" \
          --name "$COMPUTE" \
          --resource-id "$AKS_ID" \
          --type kubernetes
        echo "Kubernetes compute target '$COMPUTE' attached."
      fi
    EOT
  }

  depends_on = [
    null_resource.aml_extension,
    azurerm_machine_learning_workspace.main,
  ]
}
