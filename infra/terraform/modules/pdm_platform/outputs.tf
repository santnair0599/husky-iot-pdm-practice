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
  value = local.synapse_name
}

output "synapse_sql_serverless_endpoint" {
  value = local.synapse_sql_endpoint
}

output "synapse_mode" {
  value = var.synapse_mode
}

output "data_connection_created" {
  value = var.create_data_connection
}
