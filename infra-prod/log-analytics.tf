resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.common_tags
}

resource "azurerm_application_insights" "main" {
  name                = "appi-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = local.common_tags
}

# AKS → Log Analytics: cluster logs + container insights
resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "diag-aks-${local.name_prefix}"
  target_resource_id         = azurerm_kubernetes_cluster.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# ML workspace → Log Analytics: job runs, endpoint calls, model events
resource "azurerm_monitor_diagnostic_setting" "ml_workspace" {
  name                       = "diag-mlw-${local.name_prefix}"
  target_resource_id         = azurerm_machine_learning_workspace.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Alert: endpoint error rate > 5% over 5 minutes
resource "azurerm_monitor_metric_alert" "endpoint_errors" {
  name                = "alert-endpoint-errors-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_application_insights.main.id]
  description         = "Fires when prod endpoint error rate exceeds 5% — investigate model or AKS health"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "microsoft.insights/components"
    metric_name      = "requests/failed"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 5
  }

  action {
    action_group_id = azurerm_monitor_action_group.drift_alerts.id
  }

  tags = local.common_tags

  depends_on = [azurerm_monitor_action_group.drift_alerts]
}

# Alert: endpoint p95 latency > 3 seconds
resource "azurerm_monitor_metric_alert" "endpoint_latency" {
  name                = "alert-endpoint-latency-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_application_insights.main.id]
  description         = "Fires when prod endpoint p95 response time exceeds 3 s"
  severity            = 3
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "microsoft.insights/components"
    metric_name      = "requests/duration"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 3000
  }

  action {
    action_group_id = azurerm_monitor_action_group.drift_alerts.id
  }

  tags = local.common_tags

  depends_on = [azurerm_monitor_action_group.drift_alerts]
}
