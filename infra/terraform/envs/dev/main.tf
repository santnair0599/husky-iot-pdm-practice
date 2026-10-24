
resource "azurerm_resource_group" "pdm" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    project     = "husky-iot-pdm"
    environment = var.environment
    managed_by  = "terraform"
  }
}


resource "azurerm_storage_account" "lake" {
  name                = var.storage_account_name
  resource_group_name = azurerm_resource_group.pdm.name
  location            = azurerm_resource_group.pdm.location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  is_hns_enabled                  = true
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  default_to_oauth_authentication = true

  tags = {
    project     = "husky-iot-pdm"
    environment = var.environment
    managed_by  = "terraform"
  }
}


resource "azurerm_storage_container" "lake" {
  for_each = toset([
    "raw",
    "curated",
    "quarantine",
    "synapse"
  ])

  name                  = each.key
  storage_account_id    = azurerm_storage_account.lake.id
  container_access_type = "private"
}

resource "azurerm_iothub" "pdm" {
  name                      = var.iot_hub_name
  resource_group_name       = azurerm_resource_group.pdm.name
  location                  = azurerm_resource_group.pdm.location
  event_hub_partition_count = 2
  identity {
    type = "SystemAssigned"
  }
  sku {
    name     = "F1"
    capacity = 1
  }

  tags = {
    project     = "husky-iot-pdm"
    environment = var.environment
    managed_by  = "terraform"
  }
}
