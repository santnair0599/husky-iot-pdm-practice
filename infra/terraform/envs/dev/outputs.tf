
output "resource_group_name" {
  value = azurerm_resource_group.pdm.name
}

output "storage_account_name" {
  value = azurerm_storage_account.lake.name
}

output "storage_account_id" {
  value = azurerm_storage_account.lake.id
}

output "iot_hub_name" {
  value = azurerm_iothub.pdm.name
}

output "lake_containers" {
  value = [
    for container in azurerm_storage_container.lake :
    container.name
  ]
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

