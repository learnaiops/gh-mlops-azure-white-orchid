locals {
  dashboard_name = "dash-${local.name_prefix}"
}

resource "azurerm_portal_dashboard" "main" {
  name                = local.dashboard_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = merge(local.common_tags, { hidden-title = "White Orchid Prod — Model & API Monitor" })

  dashboard_properties = jsonencode({
    lenses = {
      "0" = {
        order = 0
        parts = {
          "0" = {
            position = { x = 0, y = 0, colSpan = 12, rowSpan = 1 }
            metadata = {
              type = "Extension/HubsExtension/PartType/MarkdownPart"
              inputs = []
              settings = {
                content = {
                  settings = {
                    content  = "## White Orchid · Production Model Monitor\nAKS Kubernetes endpoint · westeurope · drift monitoring enabled"
                    title    = ""
                    subtitle = ""
                    markdownSource = 1
                  }
                }
              }
            }
          }
          "1" = {
            position = { x = 0, y = 1, colSpan = 4, rowSpan = 3 }
            metadata = {
              type = "Extension/Microsoft_Azure_Monitoring/PartType/MetricsChartPart"
              inputs = [
                {
                  name  = "options"
                  value = {
                    chart = {
                      metrics = [
                        {
                          resourceMetadata = { id = azurerm_application_insights.main.id }
                          name             = "requests/count"
                          aggregationType  = 7
                          namespace        = "microsoft.insights/components"
                          metricVisualization = { displayName = "Server requests" }
                        }
                      ]
                      title       = "Endpoint Requests / min"
                      titleKind   = 1
                      visualization = {
                        chartType  = 2
                        legendVisualization = { isVisible = true, position = 2, hideSubtitle = false }
                        axisVisualization   = {
                          x = { isVisible = true, axisType = 2 }
                          y = { isVisible = true, axisType = 1 }
                        }
                      }
                      timespan = { relative = { duration = 86400000 } }
                    }
                  }
                }
              ]
            }
          }
          "2" = {
            position = { x = 4, y = 1, colSpan = 4, rowSpan = 3 }
            metadata = {
              type = "Extension/Microsoft_Azure_Monitoring/PartType/MetricsChartPart"
              inputs = [
                {
                  name  = "options"
                  value = {
                    chart = {
                      metrics = [
                        {
                          resourceMetadata = { id = azurerm_application_insights.main.id }
                          name             = "requests/duration"
                          aggregationType  = 4
                          namespace        = "microsoft.insights/components"
                          metricVisualization = { displayName = "Response time (avg ms)" }
                        }
                      ]
                      title       = "Endpoint Avg Latency (ms)"
                      titleKind   = 1
                      visualization = {
                        chartType = 2
                        legendVisualization = { isVisible = true, position = 2, hideSubtitle = false }
                        axisVisualization   = {
                          x = { isVisible = true, axisType = 2 }
                          y = { isVisible = true, axisType = 1 }
                        }
                      }
                      timespan = { relative = { duration = 86400000 } }
                    }
                  }
                }
              ]
            }
          }
          "3" = {
            position = { x = 8, y = 1, colSpan = 4, rowSpan = 3 }
            metadata = {
              type = "Extension/Microsoft_Azure_Monitoring/PartType/MetricsChartPart"
              inputs = [
                {
                  name  = "options"
                  value = {
                    chart = {
                      metrics = [
                        {
                          resourceMetadata = { id = azurerm_application_insights.main.id }
                          name             = "requests/failed"
                          aggregationType  = 7
                          namespace        = "microsoft.insights/components"
                          metricVisualization = { displayName = "Failed requests" }
                        }
                      ]
                      title       = "Endpoint Failures / min"
                      titleKind   = 1
                      visualization = {
                        chartType = 2
                        legendVisualization = { isVisible = true, position = 2, hideSubtitle = false }
                        axisVisualization   = {
                          x = { isVisible = true, axisType = 2 }
                          y = { isVisible = true, axisType = 1 }
                        }
                      }
                      timespan = { relative = { duration = 86400000 } }
                    }
                  }
                }
              ]
            }
          }
          "4" = {
            position = { x = 0, y = 4, colSpan = 6, rowSpan = 3 }
            metadata = {
              type = "Extension/Microsoft_Azure_Monitoring/PartType/MetricsChartPart"
              inputs = [
                {
                  name  = "options"
                  value = {
                    chart = {
                      metrics = [
                        {
                          resourceMetadata = { id = azurerm_kubernetes_cluster.main.id }
                          name             = "node_cpu_usage_percentage"
                          aggregationType  = 4
                          namespace        = "microsoft.containerservice/managedclusters"
                          metricVisualization = { displayName = "Node CPU %" }
                        }
                      ]
                      title       = "AKS Node CPU Usage"
                      titleKind   = 1
                      visualization = {
                        chartType = 2
                        legendVisualization = { isVisible = true, position = 2, hideSubtitle = false }
                        axisVisualization   = {
                          x = { isVisible = true, axisType = 2 }
                          y = { isVisible = true, axisType = 1 }
                        }
                      }
                      timespan = { relative = { duration = 86400000 } }
                    }
                  }
                }
              ]
            }
          }
          "5" = {
            position = { x = 6, y = 4, colSpan = 6, rowSpan = 3 }
            metadata = {
              type = "Extension/Microsoft_Azure_Monitoring/PartType/MetricsChartPart"
              inputs = [
                {
                  name  = "options"
                  value = {
                    chart = {
                      metrics = [
                        {
                          resourceMetadata = { id = azurerm_kubernetes_cluster.main.id }
                          name             = "node_memory_working_set_percentage"
                          aggregationType  = 4
                          namespace        = "microsoft.containerservice/managedclusters"
                          metricVisualization = { displayName = "Node Memory %" }
                        }
                      ]
                      title       = "AKS Node Memory Usage"
                      titleKind   = 1
                      visualization = {
                        chartType = 2
                        legendVisualization = { isVisible = true, position = 2, hideSubtitle = false }
                        axisVisualization   = {
                          x = { isVisible = true, axisType = 2 }
                          y = { isVisible = true, axisType = 1 }
                        }
                      }
                      timespan = { relative = { duration = 86400000 } }
                    }
                  }
                }
              ]
            }
          }
          "6" = {
            position = { x = 0, y = 7, colSpan = 6, rowSpan = 3 }
            metadata = {
              type = "Extension/Microsoft_Azure_Monitoring/PartType/MetricsChartPart"
              inputs = [
                {
                  name  = "options"
                  value = {
                    chart = {
                      metrics = [
                        {
                          resourceMetadata = { id = azurerm_kubernetes_cluster.main.id }
                          name             = "kube_pod_status_ready"
                          aggregationType  = 7
                          namespace        = "microsoft.containerservice/managedclusters"
                          metricVisualization = { displayName = "Ready pods" }
                        }
                      ]
                      title       = "AKS Ready Pods"
                      titleKind   = 1
                      visualization = {
                        chartType = 2
                        legendVisualization = { isVisible = true, position = 2, hideSubtitle = false }
                        axisVisualization   = {
                          x = { isVisible = true, axisType = 2 }
                          y = { isVisible = true, axisType = 1 }
                        }
                      }
                      timespan = { relative = { duration = 86400000 } }
                    }
                  }
                }
              ]
            }
          }
          "7" = {
            position = { x = 6, y = 7, colSpan = 6, rowSpan = 3 }
            metadata = {
              type = "Extension/Microsoft_Azure_Monitoring/PartType/MetricsChartPart"
              inputs = [
                {
                  name  = "options"
                  value = {
                    chart = {
                      metrics = [
                        {
                          resourceMetadata = { id = azurerm_application_insights.main.id }
                          name             = "exceptions/count"
                          aggregationType  = 7
                          namespace        = "microsoft.insights/components"
                          metricVisualization = { displayName = "Exceptions" }
                        }
                      ]
                      title       = "App Insights Exceptions"
                      titleKind   = 1
                      visualization = {
                        chartType = 2
                        legendVisualization = { isVisible = true, position = 2, hideSubtitle = false }
                        axisVisualization   = {
                          x = { isVisible = true, axisType = 2 }
                          y = { isVisible = true, axisType = 1 }
                        }
                      }
                      timespan = { relative = { duration = 86400000 } }
                    }
                  }
                }
              ]
            }
          }
          "8" = {
            position = { x = 0, y = 10, colSpan = 12, rowSpan = 1 }
            metadata = {
              type = "Extension/HubsExtension/PartType/MarkdownPart"
              inputs = []
              settings = {
                content = {
                  settings = {
                    content  = "### Drift Monitoring\nOpen **Azure ML Studio → Jobs → Monitoring** to see the `white-orchid-risk-prod-monitor` daily drift report. Re-run `terraform apply` after first deploy to activate data collection and the monitoring schedule."
                    title    = ""
                    subtitle = ""
                    markdownSource = 1
                  }
                }
              }
            }
          }
        }
      }
    }
    metadata = {
      model = {
        timeRange = {
          value = { relative = { duration = 86400000 } }
          type  = "MsPortalFx.Composition.Configuration.ValueTypes.TimeRange"
        }
      }
    }
  })
}
