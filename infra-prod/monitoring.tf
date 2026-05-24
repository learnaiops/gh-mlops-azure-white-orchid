# Enables model data collection on the prod deployment so scored inputs and
# outputs are written to the storage account. Required before creating a
# drift monitoring schedule.
#
# NOTE: This null_resource skips gracefully when the endpoint/deployment do not
# exist yet. Re-run `terraform apply` after the first pipeline run to activate.
resource "null_resource" "enable_data_collection" {
  triggers = {
    workspace_id = azurerm_machine_learning_workspace.main.id
  }

  provisioner "local-exec" {
    environment = {
      MLW_RG     = azurerm_resource_group.main.name
      MLW_NAME   = azurerm_machine_learning_workspace.main.name
      EP_NAME    = var.prod_endpoint_name
      DP_NAME    = var.prod_deployment_name
    }
    command = <<-EOT
      set -e
      az extension add --name ml --upgrade --yes 2>/dev/null || true

      DP_STATE=$(az ml online-deployment show \
        --resource-group "$MLW_RG" \
        --workspace-name "$MLW_NAME" \
        --endpoint-name "$EP_NAME" \
        --name "$DP_NAME" \
        --query provisioningState -o tsv 2>/dev/null || echo "NotFound")

      if [ "$DP_STATE" != "Succeeded" ]; then
        echo "Deployment '$DP_NAME' not found or not ready — skipping data collection setup."
        echo "Re-run 'terraform apply' after the first model-promote pipeline run."
        exit 0
      fi

      echo "Enabling model data collection on $EP_NAME/$DP_NAME..."
      az ml online-deployment update \
        --resource-group "$MLW_RG" \
        --workspace-name "$MLW_NAME" \
        --endpoint-name "$EP_NAME" \
        --name "$DP_NAME" \
        --set data_collector.sampling_rate=1.0 \
               data_collector.collections.model_inputs.enabled=true \
               data_collector.collections.model_inputs.data_collector_mode=ReadWrite \
               data_collector.collections.model_outputs.enabled=true \
               data_collector.collections.model_outputs.data_collector_mode=ReadWrite
      echo "Data collection enabled."
    EOT
  }

  depends_on = [
    null_resource.aml_compute_attach,
    azurerm_machine_learning_workspace.main,
    azurerm_role_assignment.mlw_storage_blob,
  ]
}

# Creates a daily Azure ML monitoring schedule that detects data drift and
# prediction drift between production traffic and the training baseline.
#
# NOTE: Skips gracefully if the endpoint is not deployed. Re-run terraform
# apply after the first pipeline run to activate monitoring.
resource "null_resource" "drift_monitor_schedule" {
  triggers = {
    workspace_id = azurerm_machine_learning_workspace.main.id
    monitor_name = "white-orchid-risk-prod-monitor"
  }

  provisioner "local-exec" {
    environment = {
      MLW_RG     = azurerm_resource_group.main.name
      MLW_NAME   = azurerm_machine_learning_workspace.main.name
      EP_NAME    = var.prod_endpoint_name
      DP_NAME    = var.prod_deployment_name
      MONITOR    = "white-orchid-risk-prod-monitor"
    }
    command = <<-EOT
      set -e
      az extension add --name ml --upgrade --yes 2>/dev/null || true

      DP_STATE=$(az ml online-deployment show \
        --resource-group "$MLW_RG" \
        --workspace-name "$MLW_NAME" \
        --endpoint-name "$EP_NAME" \
        --name "$DP_NAME" \
        --query provisioningState -o tsv 2>/dev/null || echo "NotFound")

      if [ "$DP_STATE" != "Succeeded" ]; then
        echo "Deployment not ready — skipping monitor schedule creation."
        exit 0
      fi

      EXISTING=$(az ml schedule show \
        --resource-group "$MLW_RG" \
        --workspace-name "$MLW_NAME" \
        --name "$MONITOR" \
        --query name -o tsv 2>/dev/null || echo "")

      if [ -n "$EXISTING" ]; then
        echo "Monitor schedule '$MONITOR' already exists — skipping."
        exit 0
      fi

      cat > /tmp/drift_monitor.yml << YAML
\$schema: https://azuremlschemas.azureedge.net/latest/monitorSchedule.schema.json
name: $MONITOR
trigger:
  type: recurrence
  frequency: day
  interval: 1
create_monitor:
  compute:
    instance_type: standard_e4s_v3
    runtime_version: "3.3"
  monitoring_signals:
    data_drift:
      type: data_drift
      production_data:
        input_data:
          type: rolling_window
          window_offset: P0D
          window_size: P1D
        data_context: model_inputs
        pre_processing_component: azureml://registries/azureml/components/data_drift_signal_monitor/versions/0.3.2
      reference_data:
        input_data:
          type: training_data
        data_context: training
        target_column_name: high_risk
      features:
        all_features: {}
      alert_enabled: true
      alert_thresholds:
        numerical:
          normalized_wasserstein_distance: 0.1
        categorical:
          jensen_shannon_divergence: 0.1
    prediction_drift:
      type: prediction_drift
      production_data:
        input_data:
          type: rolling_window
          window_offset: P0D
          window_size: P1D
        data_context: model_outputs
      reference_data:
        input_data:
          type: training_data
        data_context: training
        target_column_name: high_risk
      alert_enabled: true
YAML

      az ml schedule create \
        --resource-group "$MLW_RG" \
        --workspace-name "$MLW_NAME" \
        --file /tmp/drift_monitor.yml
      echo "Drift monitor schedule '$MONITOR' created."
    EOT
  }

  depends_on = [null_resource.enable_data_collection]
}
