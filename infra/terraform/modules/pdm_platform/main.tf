# Reusable Husky platform for one environment: lake, IoT Hub with dual routing,
# ADX, Synapse and monitoring. Built from the verified Dev configuration
# (infra/terraform/envs/dev), which is not yet migrated to this module.
#
# Deliberately NOT in this module (admin-only, see docs/test-environment.md):
# the resource group, the deployer identity, ADX principal assignments and
# Synapse SQL admins/grants. The deployer must not be able to grant itself access.

locals {
  tags = {
    project     = "husky-iot-pdm"
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "azurerm_storage_account" "lake" {
  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  is_hns_enabled                  = true
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  default_to_oauth_authentication = true

  tags = local.tags
}

resource "azurerm_storage_container" "lake" {
  for_each = toset(["raw", "curated", "synapse"])

  name                  = each.key
  storage_account_id    = azurerm_storage_account.lake.id
  container_access_type = "private"
}

resource "azurerm_iothub" "pdm" {
  name                      = var.iot_hub_name
  resource_group_name       = var.resource_group_name
  location                  = var.location
  event_hub_partition_count = 2

  identity {
    type = "SystemAssigned"
  }

  sku {
    name     = var.iot_hub_sku
    capacity = 1
  }

  tags = local.tags
}

# Role assignments to MANAGED identities only. The deployer can create these
# because its RBAC delegation is limited by an Azure condition to the two blob
# data roles, service principals, and never itself (infra/bootstrap-env).
resource "azurerm_role_assignment" "iot_raw_writer" {
  scope                = azurerm_storage_container.lake["raw"].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_iothub.pdm.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_iothub_endpoint_storage_container" "raw" {
  name                = "raw-telemetry"
  resource_group_name = var.resource_group_name
  iothub_id           = azurerm_iothub.pdm.id

  container_name      = azurerm_storage_container.lake["raw"].name
  authentication_type = "identityBased"
  endpoint_uri        = azurerm_storage_account.lake.primary_blob_endpoint

  encoding                   = "JSON"
  batch_frequency_in_seconds = 60
  max_chunk_size_in_bytes    = 10485760
  file_name_format           = "{iothub}/{partition}/{YYYY}/{MM}/{DD}/{HH}/{mm}"

  depends_on = [azurerm_role_assignment.iot_raw_writer]
}

resource "azurerm_iothub_route" "archive" {
  name                = "route-raw-archive"
  resource_group_name = var.resource_group_name
  iothub_name         = azurerm_iothub.pdm.name

  source         = "DeviceMessages"
  condition      = "true"
  endpoint_names = [azurerm_iothub_endpoint_storage_container.raw.name]
  enabled        = true
}

resource "azurerm_iothub_route" "live" {
  name                = "route-live-events"
  resource_group_name = var.resource_group_name
  iothub_name         = azurerm_iothub.pdm.name

  source         = "DeviceMessages"
  condition      = "true"
  endpoint_names = ["events"]
  enabled        = true
}
