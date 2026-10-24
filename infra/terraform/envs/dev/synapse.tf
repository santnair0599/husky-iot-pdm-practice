resource "azurerm_synapse_workspace" "pdm" {
  name                        = var.synapse_workspace_name
  resource_group_name         = azurerm_resource_group.pdm.name
  location                    = var.synapse_location
  managed_resource_group_name = var.synapse_managed_resource_group_name

  storage_data_lake_gen2_filesystem_id = "${azurerm_storage_account.lake.primary_dfs_endpoint}${azurerm_storage_container.lake["synapse"].name}"

  sql_administrator_login       = "sqladminuser"
  azuread_authentication_only   = true
  public_network_access_enabled = true

  identity {
    type = "SystemAssigned"
  }

  tags = {
    project     = "husky-iot-pdm"
    environment = var.environment
    managed_by  = "terraform"
  }
}

# Lab only: open to all IPs. Restrict to known IPs in the security module.
resource "azurerm_synapse_firewall_rule" "allow_all" {
  name                 = "allowAll"
  synapse_workspace_id = azurerm_synapse_workspace.pdm.id
  start_ip_address     = "0.0.0.0"
  end_ip_address       = "255.255.255.255"
}

resource "azurerm_role_assignment" "synapse_default_fs" {
  scope                = azurerm_storage_container.lake["synapse"].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_synapse_workspace.pdm.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "synapse_curated_reader" {
  scope                = azurerm_storage_container.lake["curated"].id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_synapse_workspace.pdm.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}
