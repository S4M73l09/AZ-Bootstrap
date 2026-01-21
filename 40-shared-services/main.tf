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

variable "shared_rg_name" {
  description = "Resource group for shared services."
  type        = string
  default     = "rg-bootstrap-shared"
}

variable "location" {
  description = "Azure region for shared services."
  type        = string
  default     = "westeurope"
}

variable "network_rg_name" {
  description = "Resource group containing the network."
  type        = string
  default     = "network-Bootstrap"
}

variable "vnet_name" {
  description = "Virtual network name."
  type        = string
  default     = "vnet-bootstrap"
}

variable "subnet_name" {
  description = "Subnet name for the runner VM."
  type        = string
  default     = "snet-runner"
}

variable "subnet_cidr" {
  description = "Subnet address prefix for the runner VM."
  type        = list(string)
  default     = ["10.10.2.0/24"]
}

variable "vm_name" {
  description = "Runner VM name."
  type        = string
  default     = "vm-bootstrap-runner"
}

variable "vm_size" {
  description = "Runner VM size."
  type        = string
  default     = "Standard_B1s"
}

variable "admin_username" {
  description = "Admin username for the runner VM."
  type        = string
  default     = "runneradmin"
}

variable "ssh_public_key" {
  description = "SSH public key for the runner VM."
  type        = string
  default     = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC9YXFPZr2rbVzvswG5eykXSdGp5ibhN8QeEBAZrZwHL9SrW2/tDUPyDcUj4CNVdg7wVuY8w56RCCTQZ7W/VsFHMHk4JX02jl6K4EAHBuFNX2z1fSTSrkh2cYgdVGmqAxBJHqgTev5lW4OKiX/GFHLK3L87lOFatsgPQZ78TsgMc2PbDPUc4Y4oT1BfE1MkyTNwf9T9FWW+vJ7WArewvOFmNCbxZPoc69aLzYY3g6V7coSU3xnUrlO94rr+3+EOg3+VXA1B6gPlKG/sKQaoBQ1dm1sX4vLJfJWkqt345hsGXyTTkBmc8c2mESKuflmWXT+WSVr0DbWQQkCVPXYUDRzbYKEn/ZsREDnY1QY0byY/cDE7DSnYTN+KMKreUuQFxVO7wW7CZSY3jjVMixnNb51CUgbXS86T0IS8j/aT668jk3Mcbt8WsvJvc68Q+V38dDwsbU4LaDJHGxjyt1SehVnrhQxiaIF+ScvLFgM2HX82euvpQ5voqY9jA+WqNikYY0wwCwPy7rotVBH+mrpExNaPUwHCc9E5fy0fsPWieHW/odl1hIFOGOddMynYWRI4Gv7yY4PJzk7Z7kpYjvWq+5f1PxvupAbULOc+KPL6uY5bWJwQSaeI1ekC5URdWfKclkEz2UqCAREr48PTDttuZE7An///9EhWbJmZmva8UJUUmQ== runneradmin"
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed to SSH to the runner VM (tighten in production)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

data "azurerm_resource_group" "network" {
  name = var.network_rg_name
}

data "azurerm_virtual_network" "bootstrap" {
  name                = var.vnet_name
  resource_group_name = data.azurerm_resource_group.network.name
}

resource "azurerm_resource_group" "shared" {
  name     = var.shared_rg_name
  location = var.location
}

resource "azurerm_subnet" "runner" {
  name                 = var.subnet_name
  resource_group_name  = data.azurerm_resource_group.network.name
  virtual_network_name = data.azurerm_virtual_network.bootstrap.name
  address_prefixes     = var.subnet_cidr
}

resource "azurerm_network_security_group" "runner" {
  name                = "nsg-bootstrap-runner"
  location            = azurerm_resource_group.shared.location
  resource_group_name = azurerm_resource_group.shared.name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.ssh_allowed_cidrs
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "runner" {
  name                = "pip-bootstrap-runner"
  location            = azurerm_resource_group.shared.location
  resource_group_name = azurerm_resource_group.shared.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "runner" {
  name                = "nic-bootstrap-runner"
  location            = azurerm_resource_group.shared.location
  resource_group_name = azurerm_resource_group.shared.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.runner.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.runner.id
  }
}

resource "azurerm_network_interface_security_group_association" "runner" {
  network_interface_id      = azurerm_network_interface.runner.id
  network_security_group_id = azurerm_network_security_group.runner.id
}

resource "azurerm_linux_virtual_machine" "runner" {
  name                = var.vm_name
  resource_group_name = azurerm_resource_group.shared.name
  location            = azurerm_resource_group.shared.location
  size                = var.vm_size
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.runner.id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}
