terraform {
  required_version = "= 1.14.3"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 3.117.1"
    }
  }
}