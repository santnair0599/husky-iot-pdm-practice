resource "azurerm_log_analytics_workspace" "pdm" {
  name                = "law-husky-pdm-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = var.log_daily_quota_gb

  tags = local.tags
}

resource "azurerm_monitor_action_group" "ops" {
  name                = "ag-husky-pdm-${var.environment}"
  resource_group_name = var.resource_group_name
  short_name          = substr("Husky${title(var.environment)}", 0, 12)

  email_receiver {
    name                    = "${var.environment}-operator"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }

  tags = local.tags
}

# "Dedicated" resource-specific mode is not persisted by Azure for ADX and causes drift
resource "azurerm_monitor_diagnostic_setting" "adx" {
  name                       = "diag-adx-to-law"
  target_resource_id         = azurerm_kusto_cluster.pdm.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.pdm.id

  enabled_log {
    category = "SucceededIngestion"
  }

  enabled_log {
    category = "FailedIngestion"
  }

  enabled_log {
    category = "IngestionBatching"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "iothub" {
  name                       = "diag-iothub-to-law"
  target_resource_id         = azurerm_iothub.pdm.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.pdm.id

  enabled_log {
    category = "Connections"
  }

  enabled_log {
    category = "Routes"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_metric_alert" "adx_ingestion_failed" {
  name                = "alert-adx-ingestion-failed-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_kusto_cluster.pdm.id]
  description         = "ADX ingestion failed. Runbook: docs/runbooks.md section 2"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.Kusto/clusters"
    metric_name      = "IngestionResult"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0

    dimension {
      name     = "IngestionResultDetails"
      operator = "Exclude"
      values   = ["Success"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops.id
  }

  tags = local.tags
}

resource "azurerm_monitor_metric_alert" "adx_export_failed" {
  name                = "alert-adx-export-failed-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_kusto_cluster.pdm.id]
  description         = "Continuous export TelemetryHistoricalExport failed. Runbook: docs/runbooks.md section 4"
  severity            = 2
  frequency           = "PT15M"
  window_size         = "PT30M"

  criteria {
    metric_namespace = "Microsoft.Kusto/clusters"
    metric_name      = "ContinuousExportResult"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 0

    dimension {
      name     = "ContinuousExportName"
      operator = "Include"
      values   = ["TelemetryHistoricalExport"]
    }

    dimension {
      name     = "Result"
      operator = "Exclude"
      values   = ["Success"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops.id
  }

  tags = local.tags
}
