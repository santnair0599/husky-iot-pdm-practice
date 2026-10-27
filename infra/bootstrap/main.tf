terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
  storage_use_azuread = true
}

resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

resource "azurerm_resource_group" "state" {
  name     = "rg-husky-pdm-tfstate"
  location = "eastus2"

  tags = {
    project = "husky-pdm"
    purpose = "terraform-state"
  }
}

resource "azurerm_storage_account" "state" {
  name = "sthpdm${random_string.suffix.result}"

  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false

  shared_access_key_enabled       = false
  default_to_oauth_authentication = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = {
    project = "husky-pdm"
    purpose = "terraform-state"
  }
}

resource "azurerm_storage_container" "state" {
  for_each = toset([
    "tfstate-dev",
    "tfstate-test",
    "tfstate-prod"
  ])

  name                  = each.key
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}