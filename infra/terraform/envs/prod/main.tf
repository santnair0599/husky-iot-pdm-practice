
# Prod environment. The resource group, deployer identity and every grant that
# widens the deployer's access are created by an admin (docs/prod-environment.md),
# never by this configuration or its workflow.
#
# Do NOT copy files from envs/dev into this folder: they hard-code Dev names
# (pdm_dev, adx-dev, law-husky-pdm-dev, ...) and Dev's deployer identity.

data "azurerm_resource_group" "prod" {
  name = var.resource_group_name
}

module "platform" {
  source = "../../modules/pdm_platform"

  environment         = var.environment
  resource_group_name = data.azurerm_resource_group.prod.name
  location            = var.location

  storage_account_name = var.storage_account_name

  iot_hub_name = var.iot_hub_name
  iot_hub_sku  = var.iot_hub_sku

  adx_cluster_name       = var.adx_cluster_name
  adx_database_name      = var.adx_database_name
  create_data_connection = var.create_data_connection

  # The ADMIN creates the Prod workspace, so a human (not the pipeline) is its
  # first Synapse Administrator and Entra SQL admin. See docs/prod-environment.md.
  synapse_mode                        = var.synapse_mode
  synapse_workspace_name              = var.synapse_workspace_name
  synapse_location                    = var.synapse_location
  synapse_managed_resource_group_name = var.synapse_managed_resource_group_name
  # No permanent rules: deploy-app-prod.yml opens the firewall for the runner's
  # own IP for one run only. Admins add a temporary rule for their IP the same way.
  synapse_firewall_ip_ranges = {}

  alert_email = var.alert_email
}
