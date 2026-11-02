
# Partial configuration. The workflow passes:
#   storage_account_name=<TF_STATE_STORAGE_ACCOUNT>  container_name=tfstate-prod  key=husky-prod.tfstate
# The Prod deployer can only reach the tfstate-prod container.
terraform {
  backend "azurerm" {
    use_azuread_auth = true
  }
}
