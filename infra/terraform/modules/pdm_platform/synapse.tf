# synapse_mode:
#   "create"   - Terraform creates the workspace (Dev-style; used by Test). The
#                creator becomes its only Synapse Administrator and Entra SQL
#                admin, which Test had to hand back to a human afterwards.
#   "existing" - an ADMIN created the workspace (Prod). Terraform only reads it
#                and grants its managed identity access to the lake.
#   "none"     - no Synapse yet (Prod first apply, before the admin creates it).
locals {
  synapse_create  = var.synapse_mode == "create"
  synapse_enabled = var.synapse_mode != "none"

  # Pick plain attributes only: the whole workspace object contains a sensitive
  # field, and passing it around would mark every derived value as sensitive.
  synapse_id = (local.synapse_create ? azurerm_synapse_workspace.pdm[0].id
  : local.synapse_enabled ? data.azurerm_synapse_workspace.existing[0].id : null)
  synapse_name = (local.synapse_create ? azurerm_synapse_workspace.pdm[0].name
  : local.synapse_enabled ? data.azurerm_synapse_workspace.existing[0].name : null)
  synapse_sql_endpoint = (local.synapse_create ? azurerm_synapse_workspace.pdm[0].connectivity_endpoints["sqlOnDemand"]
  : local.synapse_enabled ? data.azurerm_synapse_workspace.existing[0].connectivity_endpoints["sqlOnDemand"] : null)
  synapse_principal = (local.synapse_create ? azurerm_synapse_workspace.pdm[0].identity[0].principal_id
  : local.synapse_enabled ? data.azurerm_synapse_workspace.existing[0].identity[0].principal_id : null)
}

resource "azurerm_synapse_workspace" "pdm" {
  count = local.synapse_create ? 1 : 0

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

data "azurerm_synapse_workspace" "existing" {
  count = var.synapse_mode == "existing" ? 1 : 0

  name                = var.synapse_workspace_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_synapse_firewall_rule" "allowed" {
  for_each = local.synapse_enabled ? var.synapse_firewall_ip_ranges : {}

  name                 = each.key
  synapse_workspace_id = local.synapse_id
  start_ip_address     = each.value.start
  end_ip_address       = each.value.end
}

resource "azurerm_role_assignment" "synapse_default_fs" {
  count = local.synapse_enabled ? 1 : 0

  scope                = azurerm_storage_container.lake["synapse"].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = local.synapse_principal
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "synapse_curated_reader" {
  count = local.synapse_enabled ? 1 : 0

  scope                = azurerm_storage_container.lake["curated"].id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = local.synapse_principal
  principal_type       = "ServicePrincipal"
}

# Test already has these without an index; renaming in state only, nothing changes in Azure
moved {
  from = azurerm_synapse_workspace.pdm
  to   = azurerm_synapse_workspace.pdm[0]
}

moved {
  from = azurerm_role_assignment.synapse_default_fs
  to   = azurerm_role_assignment.synapse_default_fs[0]
}

moved {
  from = azurerm_role_assignment.synapse_curated_reader
  to   = azurerm_role_assignment.synapse_curated_reader[0]
}
