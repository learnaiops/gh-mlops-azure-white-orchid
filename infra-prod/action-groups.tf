# Action Group: receives all model drift and operational alerts and fans out to
# email + optional Teams channel. The webhook_receiver block is only emitted
# when teams_webhook_url is non-empty (using a dynamic block).
#
# To wire automated remediation:
#   1. Deploy a Logic App (see logic-app.tf) that calls the ADO REST API.
#   2. Set teams_webhook_url = <Logic App HTTP-trigger URL> in terraform.tfvars.
#   3. The Logic App queues drift-remediation-pipeline.yml on every alert.
resource "azurerm_monitor_action_group" "drift_alerts" {
  name                = "ag-drift-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "drift-ag"
  enabled             = true
  tags                = local.common_tags

  email_receiver {
    name                    = "mlops-engineer"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }

  dynamic "webhook_receiver" {
    for_each = var.teams_webhook_url != "" ? [1] : []
    content {
      name                    = "teams-mlops-channel"
      service_uri             = var.teams_webhook_url
      use_common_alert_schema = true
    }
  }
}
