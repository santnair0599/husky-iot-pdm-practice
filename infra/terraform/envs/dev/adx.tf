
resource "azurerm_kusto_cluster" "pdm" {
  name                = var.adx_cluster_name
  location            = azurerm_resource_group.pdm.location
  resource_group_name = azurerm_resource_group.pdm.name

  sku {
    name     = "Dev(No SLA)_Standard_E2a_v4"
    capacity = 1
  }

  tags = {
    project     = "husky-iot-pdm"
    environment = var.environment
    managed_by  = "terraform"
  }

  identity {
    type = "SystemAssigned"
  }

}

resource "azurerm_kusto_database" "pdm" {
  name                = "pdm_dev"
  resource_group_name = azurerm_resource_group.pdm.name
  location            = azurerm_resource_group.pdm.location
  cluster_name        = azurerm_kusto_cluster.pdm.name

  hot_cache_period   = "P1D"
  soft_delete_period = "P7D"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_iothub_consumer_group" "adx" {
  name                   = "adx-dev"
  resource_group_name    = azurerm_resource_group.pdm.name
  iothub_name            = azurerm_iothub.pdm.name
  eventhub_endpoint_name = "events"
}


resource "azurerm_iothub_shared_access_policy" "adx_reader" {
  name                = "adx-reader"
  resource_group_name = azurerm_resource_group.pdm.name
  iothub_name         = azurerm_iothub.pdm.name

  registry_read   = true
  service_connect = true
}

resource "azurerm_kusto_script" "raw_ingestion" {
  name        = "deploy-raw-ingestion"
  database_id = azurerm_kusto_database.pdm.id

  script_content = file(
    "${path.module}/../../../../kql/01_raw_ingestion.kql"
  )

  continue_on_errors_enabled = false
}


resource "azurerm_kusto_iothub_data_connection" "telemetry" {
  name                = "iot-telemetry-dev"
  resource_group_name = azurerm_resource_group.pdm.name
  location            = azurerm_resource_group.pdm.location

  cluster_name  = azurerm_kusto_cluster.pdm.name
  database_name = azurerm_kusto_database.pdm.name

  iothub_id                 = azurerm_iothub.pdm.id
  consumer_group            = azurerm_iothub_consumer_group.adx.name
  shared_access_policy_name = azurerm_iothub_shared_access_policy.adx_reader.name

  table_name        = "Telemetry_Raw"
  mapping_rule_name = "TelemetryRawMapping"
  data_format       = "JSON"

  event_system_properties = [
    "iothub-connection-device-id"
  ]

  depends_on = [
    azurerm_kusto_script.raw_ingestion
  ]
}


resource "azurerm_kusto_script" "dq_tables" {
  name        = "deploy-dq-tables"
  database_id = azurerm_kusto_database.pdm.id

  script_content = file(
    "${path.module}/../../../../kql/02_silver_quarantine_tables.kql"
  )

  continue_on_errors_enabled = false
}

resource "azurerm_kusto_script" "dq_functions" {
  name        = "deploy-dq-functions"
  database_id = azurerm_kusto_database.pdm.id

  script_content = file(
    "${path.module}/../../../../kql/03_validation_functions.kql"
  )

  continue_on_errors_enabled = false

  depends_on = [
    azurerm_kusto_script.raw_ingestion,
    azurerm_kusto_script.dq_tables
  ]
}

resource "azurerm_kusto_script" "dq_policies" {
  name        = "deploy-dq-policies"
  database_id = azurerm_kusto_database.pdm.id

  script_content = file(
    "${path.module}/../../../../kql/04_update_policies.kql"
  )

  continue_on_errors_enabled = false

  depends_on = [
    azurerm_kusto_script.dq_functions
  ]
}


resource "azurerm_kusto_script" "predictive_analytics" {
  name        = "deploy-predictive-analytics"
  database_id = azurerm_kusto_database.pdm.id

  script_content = join("\n\n", [
    file("${path.module}/../../../../kql/06_device_health.kql"),
    file("${path.module}/../../../../kql/07_vibration_anomalies.kql"),
    file("${path.module}/../../../../kql/08_vibration_forecast.kql"),
    file("${path.module}/../../../../kql/09_maintenance_alerts.kql")
  ])

  continue_on_errors_enabled = false

  depends_on = [
    azurerm_kusto_script.dq_functions,
    azurerm_kusto_script.dq_policies
  ]
}

resource "azurerm_kusto_cluster_principal_assignment" "admin" {
  name                = "adx-admin"
  resource_group_name = azurerm_resource_group.pdm.name
  cluster_name        = azurerm_kusto_cluster.pdm.name
  tenant_id           = "874dd38d-b50f-40f3-9c7d-8c1342244a1d"
  principal_id        = var.adx_admin_object_id
  principal_type      = "User"
  role                = "AllDatabasesAdmin"
}

