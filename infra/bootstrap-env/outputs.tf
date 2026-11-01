# Identifiers only (no secrets). Copy into the GitHub environment variables.
output "AZURE_CLIENT_ID" {
  value = azuread_application.deployer.client_id
}

output "deployer_object_id" {
  value = azuread_service_principal.deployer.object_id
}

output "resource_group_name" {
  value = azurerm_resource_group.env.name
}

output "federated_subject" {
  value = azuread_application_federated_identity_credential.github.subject
}
