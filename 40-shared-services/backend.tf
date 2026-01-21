terraform {
  backend "azurerm" {
    resource_group_name  = "rg-bootstrap-state-aq7yx"
    storage_account_name = "stbootstraptfstateaq7yx"
    container_name       = "tfboot"
    key                  = "40-shared-services.tfstate"
    use_azuread_auth     = true
  }
}
