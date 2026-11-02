output "resource_group_name" {
  value = data.azurerm_resource_group.prod.name
}

output "storage_account_name" {
  value = module.platform.storage_account_name
}

output "iot_hub_name" {
  value = module.platform.iot_hub_name
}

output "adx_cluster_name" {
  value = module.platform.adx_cluster_name
}

output "adx_cluster_uri" {
  value = module.platform.adx_cluster_uri
}

output "adx_database_name" {
  value = module.platform.adx_database_name
}

output "synapse_workspace_name" {
  value = module.platform.synapse_workspace_name
}

output "synapse_sql_serverless_endpoint" {
  value = module.platform.synapse_sql_serverless_endpoint
}

output "data_connection_created" {
  value = module.platform.data_connection_created
}

output "synapse_mode" {
  value = module.platform.synapse_mode
}
