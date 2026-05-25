# Scheduled query alert: fires when the production model's prediction
# distribution drifts beyond safe thresholds.
#
# Detection logic (evaluated every 30 min over a 1h window):
#   - avg risk_probability > 0.60  (baseline ~0.45 on training distribution)
#   - OR avg BMI > 32              (training mean ~27)
#   - OR avg age > 56              (training mean ~45)
#   - Only fires if >= 20 predictions were logged in the window
#     (prevents false alarms during low-traffic periods)
#
# Data source: App Insights events emitted by score.py on every scoring
# request. Since App Insights is workspace-based, events flow into the
# Log Analytics workspace as the AppEvents table (not customEvents —
# that name only resolves when scoped to an AI resource, not a LA workspace).
#
# Alert chain:
#   score.py → App Insights customEvents → Log Analytics
#   → this scheduled query rule
#   → action group (email + optional Teams webhook)
#   → [optional] Logic App → ADO drift-remediation-pipeline.yml
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "prediction_drift" {
  name                = "alert-prediction-drift-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # App Insights data flows through the linked LA workspace — scope to LA.
  scopes = [azurerm_log_analytics_workspace.main.id]

  severity             = 1
  description          = "Prod model prediction distribution has shifted — possible data or concept drift. Investigate and run drift-remediation-pipeline if confirmed."
  evaluation_frequency = "PT30M"
  window_duration      = "PT1H"
  enabled              = true

  criteria {
    query = <<-KQL
      AppEvents
      | where Name == "risk_prediction"
      | extend risk_prob = todouble(Properties["risk_probability"])
      | extend bmi_val   = todouble(Properties["bmi"])
      | extend age_val   = todouble(Properties["age"])
      | summarize
          record_count   = count(),
          avg_risk_prob  = avg(risk_prob),
          avg_bmi        = avg(bmi_val),
          avg_age        = avg(age_val)
      | where record_count >= 20
      | where avg_risk_prob > 0.60
           or avg_bmi > 32
           or avg_age > 56
    KQL

    # Count rows returned by the query; any row = drift threshold breached.
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.drift_alerts.id]
  }

  tags = local.common_tags

  depends_on = [azurerm_monitor_action_group.drift_alerts]
}

# Separate alert: fires when the Azure ML daily drift monitor job itself
# completes and has flagged drift in its report. Queries AML diagnostic
# logs forwarded to Log Analytics. Severity 2 (lower than the real-time
# App Insights alert above) — this is the batch confirmation signal.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "aml_monitor_drift" {
  name                = "alert-aml-monitor-drift-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  scopes = [azurerm_log_analytics_workspace.main.id]

  severity             = 2
  description          = "Azure ML daily drift monitor reported drift threshold breach. Check AML Studio > Monitoring > white-orchid-risk-prod-monitor."
  evaluation_frequency = "PT1H"
  window_duration      = "PT2H"
  enabled              = true

  criteria {
    query = <<-KQL
      AmlOnlineEndpointEventLog
      | where Message has "drift" and Message has "threshold"
      | union (
          AzureActivity
          | where OperationNameValue has "Microsoft.MachineLearningServices/workspaces/schedules"
            and ActivityStatusValue == "Success"
            and Properties has "white-orchid-risk-prod-monitor"
        )
      | project TimeGenerated, Message = coalesce(Message, tostring(Properties)), OperationName
    KQL

    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.drift_alerts.id]
  }

  tags = local.common_tags

  depends_on = [azurerm_monitor_action_group.drift_alerts]
}
