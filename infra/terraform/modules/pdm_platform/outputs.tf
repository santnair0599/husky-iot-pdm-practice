output "storage_account_name" {
  value = azurerm_storage_account.lake.name
}

output "iot_hub_name" {
  value = azurerm_iothub.pdm.name
}

output "adx_cluster_name" {
  value = azurerm_kusto_cluster.pdm.name
}

output "adx_cluster_uri" {
  value = azurerm_kusto_cluster.pdm.uri
}

output "adx_database_name" {
  value = azurerm_kusto_database.pdm.name
}

output "synapse_workspace_name" {
  value = azurerm_synapse_workspace.pdm.name
}

output "synapse_sql_serverless_endpoint" {
  value = azurerm_synapse_workspace.pdm.connectivity_endpoints["sqlOnDemand"]
}

output "data_connection_created" {
  value = var.create_data_connection
}
