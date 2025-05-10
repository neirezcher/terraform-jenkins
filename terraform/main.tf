# Configure the Azure provider
provider "azurerm" {
  features {}

  subscription_id = var.subscription
  tenant_id       = var.tenant
  #since we are using student account we do not have all permissions 
  resource_provider_registrations = "none"

  # This is an alternative authentication method using an access token
  # Note: Using access tokens directly is not recommended for production
  # as they are short-lived. Consider using service principals instead.
  use_oidc         = true
  oidc_token       = var.accessToken
}

# Create a resource group
resource "azurerm_resource_group" "TP4_devops_rg" {
  name     = "TP4-devops-resources"
  location = "France Central"
}

# Create a virtual network
resource "azurerm_virtual_network" "TP4_devops_vnet" {
  name                = "TP4-devops-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.TP4_devops_rg.location
  resource_group_name = azurerm_resource_group.TP4_devops_rg.name
}

# Create a subnet
resource "azurerm_subnet" "TP4_devops_subnet" {
  name                 = "TP4-devops-internal"
  resource_group_name  = azurerm_resource_group.TP4_devops_rg.name
  virtual_network_name = azurerm_virtual_network.TP4_devops_vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Create a public IP with Standard SKU and static allocation
resource "azurerm_public_ip" "TP4_devops_pip" {
  name                = "TP4-devops-ip"
  location            = azurerm_resource_group.TP4_devops_rg.location
  resource_group_name = azurerm_resource_group.TP4_devops_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Create a network interface
resource "azurerm_network_interface" "TP4_devops_nic" {
  name                = "TP4-devops-nic"
  location            = azurerm_resource_group.TP4_devops_rg.location
  resource_group_name = azurerm_resource_group.TP4_devops_rg.name

  ip_configuration {
    name                          = "TP4-devops-internal"
    subnet_id                     = azurerm_subnet.TP4_devops_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.TP4_devops_pip.id
  }
}

# Create the virtual machine with Ubuntu 20.04 LTS
resource "azurerm_linux_virtual_machine" "TP4_devops_vm" {
  name                = "TP4-devops-vm"
  resource_group_name = azurerm_resource_group.TP4_devops_rg.name
  location            = azurerm_resource_group.TP4_devops_rg.location
  size                = "Standard_B2s"
  admin_username      = "devopsadmin"
  network_interface_ids = [
    azurerm_network_interface.TP4_devops_nic.id,
  ]

  admin_ssh_key {
    username   = "devopsadmin"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  tags = {
    environment = "dev"
    project     = "TP4_devops"
    os          = "ubuntu-20.04"
  }
}

# Output the public IP address
output "TP4_devops_vm_public_ip" {
  value = azurerm_public_ip.TP4_devops_pip.ip_address
  description = "Public IP address of the TP4_devops VM"
}