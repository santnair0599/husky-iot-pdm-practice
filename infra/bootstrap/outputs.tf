output "state_storage_account_name" {
  value = azurerm_storage_account.state.name
}

output "state_resource_group" {
  value = azurerm_resource_group.state.name
}

output "state_container_names" {
  value = [
    for container in azurerm_storage_container.state :
    container.name
  ]
}