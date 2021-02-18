resource "random_pet" "rand" {
  prefix = var.name
}

resource "azurerm_resource_group" "rg" {
  name     = "${random_pet.rand.id}-resources"
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${random_pet.rand.id}-vnet"
  address_space       = ["10.0.0.0/16"]
  dns_servers         = ["1.1.1.2", "1.0.0.2"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "${random_pet.rand.id}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "pip" {
  name                    = "${random_pet.rand.id}-pip"
  location                = azurerm_resource_group.rg.location
  resource_group_name     = azurerm_resource_group.rg.name
  allocation_method       = "Dynamic"
  idle_timeout_in_minutes = 30
}

resource "azurerm_network_interface" "nic" {
  name                = "${random_pet.rand.id}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

data "cloudflare_ip_ranges" "cloudflare" {}

resource "azurerm_network_security_group" "nsg" {
  name                = "${random_pet.rand.id}-nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Cloudflare"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefixes    = data.cloudflare_ip_ranges.cloudflare.ipv4_cidr_blocks
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "nic-nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_linux_virtual_machine" "coder" {
  name                            = "${random_pet.rand.id}-vm"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  size                            = "Standard_B2s"
  admin_username                  = var.username
  computer_name                   = var.name
  custom_data                     = filebase64("./cloud-init.yaml")
  disable_password_authentication = true
  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  os_disk {
    name                 = "${random_pet.rand.id}-vm-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 50
  }

  admin_ssh_key {
    username   = var.username
    public_key = base64decode(var.ssh_public_key)
  }
}
