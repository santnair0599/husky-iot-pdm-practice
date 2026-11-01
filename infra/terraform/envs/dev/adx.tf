
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

# Lesson 19A: the release pipeline deploys KQL through the ADX data plane,
# which Azure RBAC (Contributor) does not cover. Admin on this ONE database only.
resource "azurerm_kusto_database_principal_assignment" "deployer" {
  name                = "github-deployer-admin"
  resource_group_name = azurerm_resource_group.pdm.name
  cluster_name        = azurerm_kusto_cluster.pdm.name
  database_name       = azurerm_kusto_database.pdm.name
  tenant_id           = "874dd38d-b50f-40f3-9c7d-8c1342244a1d"
  principal_id        = var.deployer_client_id
  principal_type      = "App"
  role                = "Admin"
}


# Lesson 19: application KQL (tables, mappings, functions, update policies,
# exports) is now owned by scripts/deploy_kql.py and deploy-app-dev.yml.
# These blocks make Terraform FORGET its old script resources without
# running or deleting anything in the database. One owner per object.

removed {
  from = azurerm_kusto_script.raw_ingestion

  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_kusto_script.dq_tables

  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_kusto_script.dq_functions

  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_kusto_script.dq_policies

  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_kusto_script.predictive_analytics

  lifecycle {
    destroy = false
  }
}
