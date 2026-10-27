
# Lesson 17 - Azure Monitor: log workspace, notifications, diagnostics, alerts

resource "azurerm_log_analytics_workspace" "dev" {
  name                = "law-husky-pdm-dev"
  location            = azurerm_resource_group.pdm.location
  resource_group_name = azurerm_resource_group.pdm.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  # Lab cost guard: stop ingesting after 0.1 GB per day
  daily_quota_gb = 0.1

  tags = {
    project     = "husky-iot-pdm"
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "azurerm_monitor_action_group" "dev_ops" {
  name                = "ag-husky-pdm-dev"
  resource_group_name = azurerm_resource_group.pdm.name
  short_name          = "HuskyDev"

  email_receiver {
    name                    = "dev-operator"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }

  tags = {
    project     = "husky-iot-pdm"
    environment = var.environment
    managed_by  = "terraform"
  }
}

# ADX ingestion logs -> AzureDiagnostics table
# ("Dedicated" resource-specific mode is not persisted by Azure for this cluster and causes drift)
resource "azurerm_monitor_diagnostic_setting" "adx" {
  name                       = "diag-adx-to-law"
  target_resource_id         = azurerm_kusto_cluster.pdm.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.dev.id

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

# IoT Hub logs -> AzureDiagnostics table
resource "azurerm_monitor_diagnostic_setting" "iothub" {
  name                       = "diag-iothub-to-law"
  target_resource_id         = azurerm_iothub.pdm.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.dev.id

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

# Any ingestion result other than Success in the last 15 minutes
resource "azurerm_monitor_metric_alert" "adx_ingestion_failed" {
  name                = "alert-adx-ingestion-failed-dev"
  resource_group_name = azurerm_resource_group.pdm.name
  scopes              = [azurerm_kusto_cluster.pdm.id]
  description         = "ADX ingestion failed. Runbook: monitoring/runbooks/ingestion.md"
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
    action_group_id = azurerm_monitor_action_group.dev_ops.id
  }

  tags = {
    project     = "husky-iot-pdm"
    environment = var.environment
    managed_by  = "terraform"
  }
}

# Any continuous-export run that did not succeed in the last 30 minutes
resource "azurerm_monitor_metric_alert" "adx_export_failed" {
  name                = "alert-adx-export-failed-dev"
  resource_group_name = azurerm_resource_group.pdm.name
  scopes              = [azurerm_kusto_cluster.pdm.id]
  description         = "Continuous export TelemetryHistoricalExport failed. Runbook: monitoring/runbooks/export.md"
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
    action_group_id = azurerm_monitor_action_group.dev_ops.id
  }

  tags = {
    project     = "husky-iot-pdm"
    environment = var.environment
    managed_by  = "terraform"
  }
}
