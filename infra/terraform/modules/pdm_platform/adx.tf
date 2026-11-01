resource "azurerm_kusto_cluster" "pdm" {
  name                = var.adx_cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name

  sku {
    name     = var.adx_sku_name
    capacity = 1
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

resource "azurerm_kusto_database" "pdm" {
  name                = var.adx_database_name
  resource_group_name = var.resource_group_name
  location            = var.location
  cluster_name        = azurerm_kusto_cluster.pdm.name

  hot_cache_period   = "P1D"
  soft_delete_period = "P7D"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_iothub_consumer_group" "adx" {
  name                   = "adx-${var.environment}"
  resource_group_name    = var.resource_group_name
  iothub_name            = azurerm_iothub.pdm.name
  eventhub_endpoint_name = "events"
}

resource "azurerm_iothub_shared_access_policy" "adx_reader" {
  name                = "adx-reader"
  resource_group_name = var.resource_group_name
  iothub_name         = azurerm_iothub.pdm.name

  registry_read   = true
  service_connect = true
}

# Needs the table and mapping first: the release pipeline (deploy-app-test.yml)
# creates them. On a brand-new environment, set create_data_connection = false
# for the first apply; see docs/test-environment.md.
resource "azurerm_kusto_iothub_data_connection" "telemetry" {
  count = var.create_data_connection ? 1 : 0

  name                = "iot-telemetry-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  cluster_name  = azurerm_kusto_cluster.pdm.name
  database_name = azurerm_kusto_database.pdm.name

  iothub_id                 = azurerm_iothub.pdm.id
  consumer_group            = azurerm_iothub_consumer_group.adx.name
  shared_access_policy_name = azurerm_iothub_shared_access_policy.adx_reader.name

  table_name        = "Telemetry_Raw"
  mapping_rule_name = "TelemetryRawMapping"
  data_format       = "JSON"

  event_system_properties = ["iothub-connection-device-id"]
}

resource "azurerm_role_assignment" "adx_curated_writer" {
  scope                = azurerm_storage_container.lake["curated"].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_kusto_cluster.pdm.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}
