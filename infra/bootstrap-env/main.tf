# ADMIN-ONLY bootstrap for one environment (test or prod). Run by a human with
# Owner + Entra app-registration rights, from a laptop, with LOCAL state:
#
#   terraform init
#   terraform workspace new test        # one workspace per environment
#   terraform plan -out=test.tfplan -var environment=test
#   terraform apply test.tfplan
#
# Never run by a pipeline. Its state stays off the shared state account, so the
# deployer it creates can never read or change its own permissions.
#
# Creates: the environment resource group, the deployer identity with a GitHub
# OIDC trust for that environment only, and the deployer's role assignments.

terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }

    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

locals {
  env = var.environment

  # Built-in role IDs (identical in every tenant)
  blob_data_contributor = "ba92f5b4-2d11-453d-a403-e96b0029c9fe"
  blob_data_reader      = "2a2b9908-6ea1-4ae2-8e65-a410df84e7d1"
  rbac_administrator    = "f58310d9-a9f6-439a-9e8d-f62e7b41a168"
}

check "workspace_matches_environment" {
  assert {
    condition     = terraform.workspace == var.environment
    error_message = "Select the matching workspace first: terraform workspace select ${var.environment}"
  }
}

data "azurerm_subscription" "current" {}

data "azurerm_storage_account" "state" {
  name                = var.state_storage_account_name
  resource_group_name = var.state_resource_group_name
}

resource "azurerm_resource_group" "env" {
  name     = "rg-husky-pdm-${local.env}"
  location = var.location

  tags = {
    project     = "husky-iot-pdm"
    environment = local.env
    managed_by  = "terraform-bootstrap-env"
  }
}

# ---------- Deployer identity, trusted only from the GitHub environment of the same name ----------

resource "azuread_application" "deployer" {
  display_name = "sp-husky-pdm-${local.env}"
}

resource "azuread_service_principal" "deployer" {
  client_id = azuread_application.deployer.client_id
}

resource "azuread_application_federated_identity_credential" "github" {
  application_id = azuread_application.deployer.id
  display_name   = "gh-husky-${local.env}-env"
  description    = "GitHub Actions jobs running in environment '${local.env}' only"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  # Immutable owner/repo IDs, same format as the Dev credential
  subject = "repo:${var.github_repository_subject}:environment:${local.env}"
}

# ---------- Deployer roles ----------

# Contributor, minus every ARM action that grants DATA-plane access.
# With built-in Contributor the deployer could make itself an ADX admin
# (principal assignments, addPrincipals, or an ARM KQL script that runs
# ".add database ... admins") or a Synapse SQL admin. That is the known Dev
# gap in docs/security.md; Test closes it here.
resource "azurerm_role_definition" "deployer" {
  name        = "Husky PDM Deployer (${local.env})"
  scope       = azurerm_resource_group.env.id
  description = "Contributor on the ${local.env} resource group without access management or data-plane admin grants"

  permissions {
    actions = ["*"]
    not_actions = [
      # Same as built-in Contributor
      "Microsoft.Authorization/*/Delete",
      "Microsoft.Authorization/*/Write",
      "Microsoft.Authorization/elevateAccess/Action",
      # ADX data-plane access
      "Microsoft.Kusto/clusters/principalAssignments/write",
      "Microsoft.Kusto/clusters/principalAssignments/delete",
      "Microsoft.Kusto/clusters/databases/principalAssignments/write",
      "Microsoft.Kusto/clusters/databases/principalAssignments/delete",
      "Microsoft.Kusto/clusters/databases/addPrincipals/action",
      "Microsoft.Kusto/clusters/databases/removePrincipals/action",
      # ARM KQL scripts (azurerm_kusto_script) have no separate action to deny:
      # Azure rejects ".../databases/scripts/write". The workflow's plan guard
      # blocks azurerm_kusto_script instead.
      # Synapse SQL Entra admin
      "Microsoft.Synapse/workspaces/administrators/write",
      "Microsoft.Synapse/workspaces/administrators/delete",
      "Microsoft.Synapse/workspaces/sqlAdministrators/write",
      "Microsoft.Synapse/workspaces/sqlAdministrators/delete",
    ]
  }

  assignable_scopes = [azurerm_resource_group.env.id]
}

resource "azurerm_role_assignment" "deployer" {
  scope              = azurerm_resource_group.env.id
  role_definition_id = azurerm_role_definition.deployer.role_definition_resource_id
  principal_id       = azuread_service_principal.deployer.object_id
  principal_type     = "ServicePrincipal"
}

# Terraform state: this environment's container only
resource "azurerm_role_assignment" "state" {
  scope                = "${data.azurerm_storage_account.state.id}/blobServices/default/containers/tfstate-${local.env}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.deployer.object_id
  principal_type       = "ServicePrincipal"
}

# Constrained delegation: the module grants managed identities blob access
# (IoT Hub -> raw, ADX -> curated, Synapse -> curated/synapse). The condition
# allows ONLY the two blob data roles, ONLY to service principals (managed
# identities are service principals), and NEVER to the deployer itself.
resource "azurerm_role_assignment" "constrained_rbac_admin" {
  scope              = azurerm_resource_group.env.id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${local.rbac_administrator}"
  principal_id       = azuread_service_principal.deployer.object_id
  principal_type     = "ServicePrincipal"
  condition_version  = "2.0"
  condition          = <<-EOT
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
     )
     OR
     (
      @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.blob_data_contributor}, ${local.blob_data_reader}}
      AND
      @Request[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'ServicePrincipal'}
      AND
      @Request[Microsoft.Authorization/roleAssignments:PrincipalId] ForAnyOfAllValues:GuidNotEquals {${azuread_service_principal.deployer.object_id}}
     )
    )
    AND
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
     )
     OR
     (
      @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.blob_data_contributor}, ${local.blob_data_reader}}
      AND
      @Resource[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'ServicePrincipal'}
     )
    )
  EOT
}
