data "cloudflare_ip_ranges" "code" {}

resource "cloudflare_record" "code" {
  zone_id = var.cloudflare_zone_id
  name    = var.name
  value   = "${var.argo_tunnel_id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

resource "cloudflare_access_application" "code" {
  zone_id                   = var.cloudflare_zone_id
  name                      = var.name
  domain                    = cloudflare_record.code.hostname
  session_duration          = "24h"
  auto_redirect_to_identity = false

  cors_headers {
    allow_all_methods     = true
    allowed_origins       = ["https://${cloudflare_record.code.hostname}"]
    allow_credentials     = true
    max_age               = 10
  }
}

resource "cloudflare_access_ca_certificate" "code" {
  application_id = cloudflare_access_application.code.id
}

data "template_file" "code-cloudflared_config" {
  template = file("./cloudflared.yml")
  vars = {
    domain    = cloudflare_record.code.hostname
    tunnel_id = var.argo_tunnel_id
  }
}

data "template_file" "code-cloudflared_auth" {
  template = file("./cloudflared.json")
  vars = {
    tunnel_id     = var.argo_tunnel_id
    tunnel_name   = var.argo_tunnel_name
    tunnel_secret = var.argo_tunnel_secret
    tunnel_tag    = var.argo_tunnel_tag
  }
}

resource "random_pet" "code" {
  prefix = var.name
}

resource "azurerm_resource_group" "code" {
  name     = random_pet.code.id
  location = var.location
}

resource "azurerm_virtual_network" "code" {
  name                = random_pet.code.id
  address_space       = ["10.0.0.0/16"]
  dns_servers         = var.dns_servers
  location            = azurerm_resource_group.code.location
  resource_group_name = azurerm_resource_group.code.name
}

resource "azurerm_subnet" "code" {
  name                 = random_pet.code.id
  resource_group_name  = azurerm_resource_group.code.name
  virtual_network_name = azurerm_virtual_network.code.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "code" {
  name                    = random_pet.code.id
  location                = azurerm_resource_group.code.location
  resource_group_name     = azurerm_resource_group.code.name
  allocation_method       = "Static"
  idle_timeout_in_minutes = 30
}

resource "azurerm_network_interface" "code" {
  name                = random_pet.code.id
  location            = azurerm_resource_group.code.location
  resource_group_name = azurerm_resource_group.code.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.code.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.code.id
  }
}

resource "azurerm_network_security_group" "code" {
  name                = random_pet.code.id
  location            = azurerm_resource_group.code.location
  resource_group_name = azurerm_resource_group.code.name
}

resource "azurerm_network_security_rule" "code-cloudflare-ipv4" {
  name                        = "AllowInboundCloudflareIPV4"
  priority                    = 101
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefixes     = data.cloudflare_ip_ranges.code.ipv4_cidr_blocks
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.code.name
  network_security_group_name = azurerm_network_security_group.code.name
}

resource "azurerm_network_security_rule" "code-cloudflare-ipv6" {
  name                        = "AllowInboundCloudflareIPV6"
  priority                    = 102
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefixes     = data.cloudflare_ip_ranges.code.ipv6_cidr_blocks
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.code.name
  network_security_group_name = azurerm_network_security_group.code.name
}

resource "azurerm_network_interface_security_group_association" "code" {
  network_interface_id      = azurerm_network_interface.code.id
  network_security_group_id = azurerm_network_security_group.code.id
}

data "template_file" "code-cloud_init" {
  template = file("./cloud-init.yaml")
  vars = {
    user_name          = var.username
    domain             = cloudflare_record.code.hostname
    ssh_ca_public_key  = base64encode(cloudflare_access_ca_certificate.code.public_key)
    cloudflared_config = base64encode(data.template_file.code-cloudflared_config.rendered)
    cloudflared_auth   = base64encode(data.template_file.code-cloudflared_auth.rendered)
  }
}

data "template_cloudinit_config" "code" {
  gzip          = true
  base64_encode = true

  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    content      = data.template_file.code-cloud_init.rendered
  }
}

resource "azurerm_linux_virtual_machine" "code" {
  name                            = random_pet.code.id
  resource_group_name             = azurerm_resource_group.code.name
  location                        = azurerm_resource_group.code.location
  size                            = "Standard_D2as_v4"
  admin_username                  = var.username
  computer_name                   = var.name
  custom_data                     = data.template_cloudinit_config.code.rendered
  disable_password_authentication = true
  network_interface_ids = [
    azurerm_network_interface.code.id,
  ]

  source_image_reference {
    publisher = "Debian"
    offer     = "debian-10"
    sku       = "10"
    version   = "latest"
  }

  os_disk {
    name                 = "${random_pet.code.id}-os"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 50
  }

  admin_ssh_key {
    username   = var.username
    public_key = var.ssh_public_key
  }
}

resource "azurerm_managed_disk" "code" {
  name                 = "${random_pet.code.id}-data"
  location             = azurerm_resource_group.code.location
  create_option        = "Empty"
  disk_size_gb         = 128
  resource_group_name  = azurerm_resource_group.code.name
  storage_account_type = "StandardSSD_LRS"
}

resource "azurerm_virtual_machine_data_disk_attachment" "code" {
  virtual_machine_id = azurerm_linux_virtual_machine.code.id
  managed_disk_id    = azurerm_managed_disk.code.id
  lun                = 0
  caching            = "None"
}
