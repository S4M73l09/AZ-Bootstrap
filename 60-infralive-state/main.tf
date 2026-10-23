resource "azurerm_resource_group" "infralive_state" {
  name     = "rg-infralive-state"
  location = "westeurope"


  tags = {
    owner      = "infralive"
    env        = "persistent"
    costCenter = "infralive"
  }
}


resource "azurerm_storage_account" "infralive_state" {
  name                            = "stinfralivest01"
  resource_group_name             = azurerm_resource_group.infralive_state.name
  location                        = azurerm_resource_group.infralive_state.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
}


resource "azurerm_storage_container" "terraform_state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.infralive_state.id
  container_access_type = "private"
}