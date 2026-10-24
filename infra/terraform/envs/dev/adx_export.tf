
resource "azurerm_role_assignment" "adx_curated_writer" {
  scope = azurerm_storage_container.lake["curated"].resource_manager_id

  role_definition_name = "Storage Blob Data Contributor"

  principal_id = azurerm_kusto_cluster.pdm.identity[0].principal_id

  principal_type = "ServicePrincipal"
}
