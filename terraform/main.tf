# Configure the Azure provider
provider "azurerm" {
  features {}

  subscription_id = var.subscription
  tenant_id       = var.tenant
  use_oidc        = true
  oidc_token      = var.accessToken
}

# Create a resource group
resource "azurerm_resource_group" "jenkins_infra_rg" {
  name     = "jenkins-infra-resources"
  location = "France Central"
}

# Create a virtual network
resource "azurerm_virtual_network" "jenkins_infra_vnet" {
  name                = "jenkins-infra-network"
  address_space       = ["10.1.0.0/16"]
  location            = azurerm_resource_group.jenkins_infra_rg.location
  resource_group_name = azurerm_resource_group.jenkins_infra_rg.name
}

# Create a subnet
resource "azurerm_subnet" "jenkins_infra_subnet" {
  name                 = "jenkins-infra-internal"
  resource_group_name  = azurerm_resource_group.jenkins_infra_rg.name
  virtual_network_name = azurerm_virtual_network.jenkins_infra_vnet.name
  address_prefixes     = ["10.1.1.0/24"]
}

# Network Security Group for SSH access
resource "azurerm_network_security_group" "jenkins_infra_nsg" {
  name                = "jenkins-infra-nsg"
  location            = azurerm_resource_group.jenkins_infra_rg.location
  resource_group_name = azurerm_resource_group.jenkins_infra_rg.name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Create a public IP
resource "azurerm_public_ip" "jenkins_infra_pip" {
  name                = "jenkins-infra-ip"
  location            = azurerm_resource_group.jenkins_infra_rg.location
  resource_group_name = azurerm_resource_group.jenkins_infra_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Create a network interface
resource "azurerm_network_interface" "jenkins_infra_nic" {
  name                = "jenkins-infra-nic"
  location            = azurerm_resource_group.jenkins_infra_rg.location
  resource_group_name = azurerm_resource_group.jenkins_infra_rg.name

  ip_configuration {
    name                          = "jenkins-infra-internal"
    subnet_id                     = azurerm_subnet.jenkins_infra_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.jenkins_infra_pip.id
  }
}

# Associate NSG with NIC
resource "azurerm_network_interface_security_group_association" "jenkins_infra_nic_nsg" {
  network_interface_id      = azurerm_network_interface.jenkins_infra_nic.id
  network_security_group_id = azurerm_network_security_group.jenkins_infra_nsg.id
}

# Create the virtual machine
resource "azurerm_linux_virtual_machine" "jenkins_infra_vm" {
  name                = "jenkins-infra-vm"
  resource_group_name = azurerm_resource_group.jenkins_infra_rg.name
  location            = azurerm_resource_group.jenkins_infra_rg.location
  size                = "Standard_B2s"
  admin_username      = "jenkinsadmin"
  network_interface_ids = [
    azurerm_network_interface.jenkins_infra_nic.id,
  ]

  admin_ssh_key {
    username   = "jenkinsadmin"
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
    environment = "prod"
    project     = "jenkins_infra"
    os          = "ubuntu-20.04"
  }
}

# Output the public IP address
output "jenkins_infra_vm_public_ip" {
  value = azurerm_public_ip.jenkins_infra_pip.ip_address
}

output "network_security_group_id" {
  value = azurerm_network_security_group.jenkins_infra_nsg.id
}