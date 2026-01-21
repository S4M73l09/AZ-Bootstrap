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

variable "bootstrap_rg_name" {
  description = "Resource group scope for bootstrap governance policies."
  type        = string
  default     = "rg-bootstrap-state-aq7yx"
}

variable "required_tags" {
  description = "Tags required on resources in the bootstrap resource group."
  type        = list(string)
  default     = ["owner", "env", "costCenter"]
}

variable "allowed_locations" {
  description = "Allowed Azure regions for resources in the bootstrap resource group."
  type        = list(string)
  default     = ["westeurope", "northeurope"]
}

data "azurerm_resource_group" "bootstrap" {
  name = var.bootstrap_rg_name
}

resource "azurerm_policy_definition" "require_tag" {
  name         = "require-tag-bootstrap"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "Require a tag on resources (bootstrap)"

  parameters = jsonencode({
    tagName = {
      type = "String"
    }
  })

  policy_rule = jsonencode({
    if = {
      field  = "[concat('tags[', parameters('tagName'), ']')]"
      exists = "false"
    }
    then = {
      effect = "deny"
    }
  })
}

resource "azurerm_policy_definition" "allowed_locations" {
  name         = "allowed-locations-bootstrap"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "Allowed locations (bootstrap)"

  parameters = jsonencode({
    allowedLocations = {
      type = "Array"
    }
  })

  policy_rule = jsonencode({
    if = {
      field = "location"
      notIn = "[parameters('allowedLocations')]"
    }
    then = {
      effect = "deny"
    }
  })
}

resource "azurerm_policy_definition" "deny_public_ip" {
  name         = "deny-public-ip-bootstrap"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "Deny Public IP (bootstrap)"

  policy_rule = jsonencode({
    if = {
      field  = "type"
      equals = "Microsoft.Network/publicIPAddresses"
    }
    then = {
      effect = "deny"
    }
  })
}

resource "azurerm_policy_set_definition" "bootstrap_governance" {
  name         = "bootstrap-governance"
  policy_type  = "Custom"
  display_name = "Bootstrap governance baseline"

  dynamic "policy_definition_reference" {
    for_each = toset(var.required_tags)
    content {
      policy_definition_id = azurerm_policy_definition.require_tag.id
      reference_id         = "require-tag-${policy_definition_reference.key}"
      parameter_values = jsonencode({
        tagName = {
          value = policy_definition_reference.key
        }
      })
    }
  }

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.allowed_locations.id
    reference_id         = "allowed-locations"
    parameter_values = jsonencode({
      allowedLocations = {
        value = var.allowed_locations
      }
    })
  }

  policy_definition_reference {
    policy_definition_id = azurerm_policy_definition.deny_public_ip.id
    reference_id         = "deny-public-ip"
  }
}

resource "azurerm_resource_group_policy_assignment" "bootstrap_governance" {
  name                 = "bootstrap-governance"
  resource_group_id    = data.azurerm_resource_group.bootstrap.id
  policy_definition_id = azurerm_policy_set_definition.bootstrap_governance.id
  description          = "Baseline governance for bootstrap resource group."
  display_name         = "Bootstrap governance baseline"
}
