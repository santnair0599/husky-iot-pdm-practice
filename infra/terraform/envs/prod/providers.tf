terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}

  # The deployer is scoped to one resource group and cannot register providers;
  # they are already registered in this subscription by Dev.
  resource_provider_registrations = "none"
}
