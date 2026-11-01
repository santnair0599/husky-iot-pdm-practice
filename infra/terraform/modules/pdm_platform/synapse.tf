resource "azurerm_synapse_workspace" "pdm" {
  name                        = var.synapse_workspace_name
  resource_group_name         = var.resource_group_name
  location                    = var.synapse_location
  managed_resource_group_name = var.synapse_managed_resource_group_name

  storage_data_lake_gen2_filesystem_id = "${azurerm_storage_account.lake.primary_dfs_endpoint}${azurerm_storage_container.lake["synapse"].name}"

  sql_administrator_login       = "sqladminuser"
  azuread_authentication_only   = true
  public_network_access_enabled = true

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

resource "azurerm_synapse_firewall_rule" "allowed" {
  for_each = var.synapse_firewall_ip_ranges

  name                 = each.key
  synapse_workspace_id = azurerm_synapse_workspace.pdm.id
  start_ip_address     = each.value.start
  end_ip_address       = each.value.end
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
