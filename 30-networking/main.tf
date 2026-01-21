terraform {
  required_version = "= 1.14.3"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 3.117.1"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "network_rg_name" {
  description = "Resource group for networking."
  type        = string
  default     = "network-Bootstrap"
}

variable "location" {
  description = "Azure region for networking."
  type        = string
  default     = "westeurope"
}

variable "vnet_name" {
  description = "Virtual network name."
  type        = string
  default     = "vnet-bootstrap"
}

variable "vnet_cidr" {
  description = "VNet address space."
  type        = list(string)
  default     = ["10.10.0.0/16"]
}

variable "subnet_name" {
  description = "Subnet name for private endpoints."
  type        = string
  default     = "snet-private-endpoints"
}

variable "subnet_cidr" {
  description = "Subnet address prefix for private endpoints."
  type        = list(string)
  default     = ["10.10.1.0/24"]
}

variable "state_rg_name" {
  description = "Resource group containing the Terraform state storage account."
  type        = string
  default     = "rg-bootstrap-state-aq7yx"
}

variable "state_storage_account_name" {
  description = "Storage account name for the Terraform state."
  type        = string
  default     = "stbootstraptfstateaq7yx"
}

variable "logging_rg_name" {
  description = "Resource group containing the logging storage account."
  type        = string
  default     = "rg-bootstraplogging-state-aq7yx"
}

variable "archive_storage_account_name" {
  description = "Storage account name for log archive."
  type        = string
  default     = "stbootlogarchaq7yx"
}

resource "azurerm_resource_group" "network" {
  name     = var.network_rg_name
  location = var.location
}

resource "azurerm_virtual_network" "bootstrap" {
  name                = var.vnet_name
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  address_space       = var.vnet_cidr
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.bootstrap.name
  address_prefixes     = var.subnet_cidr

  private_endpoint_network_policies_enabled = false
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.network.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "link-bootstrap-blob"
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.bootstrap.id
}

data "azurerm_storage_account" "state" {
  name                = var.state_storage_account_name
  resource_group_name = var.state_rg_name
}

data "azurerm_storage_account" "archive" {
  name                = var.archive_storage_account_name
  resource_group_name = var.logging_rg_name
}

resource "azurerm_private_endpoint" "state_storage" {
  name                = "pep-state-storage"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-state-storage"
    private_connection_resource_id = data.azurerm_storage_account.state.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob-zone"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

resource "azurerm_private_endpoint" "archive_storage" {
  name                = "pep-archive-storage"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-archive-storage"
    private_connection_resource_id = data.azurerm_storage_account.archive.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob-zone"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}
