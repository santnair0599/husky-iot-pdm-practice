
# Partial configuration. The workflow passes:
#   storage_account_name=<TF_STATE_STORAGE_ACCOUNT>  container_name=tfstate-test  key=husky-test.tfstate
# The Test deployer can only reach the tfstate-test container.
terraform {
  backend "azurerm" {
    use_azuread_auth = true
  }
}
