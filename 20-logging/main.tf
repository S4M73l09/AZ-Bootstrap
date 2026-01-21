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

variable "logging_rg_name" {
  description = "Resource group for logging resources."
  type        = string
  default     = "rg-bootstraplogging-state-aq7yx"
}

variable "location" {
  description = "Primary Azure region for logging resources."
  type        = string
  default     = "westeurope"
}

variable "log_analytics_retention_days" {
  description = "Log Analytics retention in days."
  type        = number
  default     = 30
}

variable "archive_storage_account_name" {
  description = "Storage account name for log archive."
  type        = string
  default     = "stbootlogarchaq7yx"
}

variable "alert_email" {
  description = "Email address to receive monitoring alerts."
  type        = string
  default     = "saminfradevops@gmail.com"
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

resource "azurerm_resource_group" "logging" {
  name     = var.logging_rg_name
  location = var.location
}

resource "azurerm_log_analytics_workspace" "bootstrap" {
  name                = "law-bootstrap-logging"
  location            = azurerm_resource_group.logging.location
  resource_group_name = azurerm_resource_group.logging.name
  retention_in_days   = var.log_analytics_retention_days
  sku                 = "PerGB2018"
}

resource "azurerm_storage_account" "archive" {
  name                            = var.archive_storage_account_name
  resource_group_name             = azurerm_resource_group.logging.name
  location                        = azurerm_resource_group.logging.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false
}

resource "azurerm_storage_management_policy" "archive_cleanup" {
  storage_account_id = azurerm_storage_account.archive.id

  rule {
    name    = "delete-logs-after-30-days"
    enabled = true

    filters {
      blob_types = ["blockBlob", "appendBlob"]
    }

    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 30
      }
    }
  }
}

data "azurerm_subscription" "current" {}

resource "azurerm_monitor_diagnostic_setting" "subscription_activity" {
  name                       = "diag-subscription-activity"
  target_resource_id         = data.azurerm_subscription.current.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.bootstrap.id
  storage_account_id         = azurerm_storage_account.archive.id

  enabled_log {
    category = "Administrative"
  }
  enabled_log {
    category = "Policy"
  }
  enabled_log {
    category = "Security"
  }
  enabled_log {
    category = "Alert"
  }
  enabled_log {
    category = "Recommendation"
  }
  enabled_log {
    category = "ServiceHealth"
  }
  enabled_log {
    category = "Autoscale"
  }
  enabled_log {
    category = "ResourceHealth"
  }
}

data "azurerm_storage_account" "state" {
  name                = var.state_storage_account_name
  resource_group_name = var.state_rg_name
}

resource "azurerm_monitor_diagnostic_setting" "state_storage" {
  name                       = "diag-storage-state"
  target_resource_id         = data.azurerm_storage_account.state.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.bootstrap.id
  storage_account_id         = azurerm_storage_account.archive.id

  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }

  metric {
    category = "Transaction"
    enabled  = true
  }
}

resource "azurerm_monitor_action_group" "bootstrap" {
  name                = "ag-bootstrap-logging"
  resource_group_name = azurerm_resource_group.logging.name
  short_name          = "bootlog"

  email_receiver {
    name          = "bootstrap-alerts"
    email_address = var.alert_email
  }
}

resource "azurerm_monitor_activity_log_alert" "rg_delete" {
  name                = "alert-rg-delete"
  resource_group_name = azurerm_resource_group.logging.name
  scopes              = [data.azurerm_subscription.current.id]
  description         = "Alert on resource group deletion."

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Resources/subscriptions/resourceGroups/delete"
    status         = "Succeeded"
  }

  action {
    action_group_id = azurerm_monitor_action_group.bootstrap.id
  }
}

resource "azurerm_monitor_activity_log_alert" "storage_delete" {
  name                = "alert-storage-delete"
  resource_group_name = azurerm_resource_group.logging.name
  scopes              = [data.azurerm_subscription.current.id]
  description         = "Alert on storage account deletion."

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Storage/storageAccounts/delete"
    status         = "Succeeded"
  }

  action {
    action_group_id = azurerm_monitor_action_group.bootstrap.id
  }
}

resource "azurerm_portal_dashboard" "bootstrap" {
  name                = "dash-bootstrap-logging"
  resource_group_name = azurerm_resource_group.logging.name
  location            = azurerm_resource_group.logging.location

  dashboard_properties = jsonencode({
    lenses = {
      "0" = {
        order = 0
        parts = {
          "0" = {
            position = {
              x       = 0
              y       = 0
              rowSpan = 4
              colSpan = 6
            }
            metadata = {
              type   = "Extension/HubsExtension/PartType/MarkdownPart"
              inputs = []
              settings = {
                content = {
                  settings = {
                    content = "Bootstrap logging dashboard\\n\\nWorkspace: ${azurerm_log_analytics_workspace.bootstrap.name}"
                  }
                }
              }
            }
          }
        }
      }
    }
    metadata = {
      model = {
        timeRange = {
          value = "Last24Hours"
          type  = "MsPortalFx.Composition.Configuration.ValueTypes.TimeRange"
        }
      }
    }
  })
}
