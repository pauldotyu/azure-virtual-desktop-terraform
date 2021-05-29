provider "azurerm" {
  features {}
}

resource "random_pet" "wvd" {
  length    = 2
  separator = ""
}

resource "azurerm_resource_group" "wvd" {
  name     = "rg-${random_pet.wvd.id}"
  location = var.location
  tags     = var.tags
}

##############################################
# VIRTUAL NETWORKING
##############################################

resource "azurerm_virtual_network" "wvd" {
  name                = "vn-${random_pet.wvd.id}"
  resource_group_name = azurerm_resource_group.wvd.name
  location            = azurerm_resource_group.wvd.location
  tags                = var.tags
  address_space       = var.vnet_address_space
  dns_servers         = var.vnet_custom_dns_servers
}

resource "azurerm_subnet" "wvd" {
  name                 = "sn-${random_pet.wvd.id}"
  resource_group_name  = azurerm_resource_group.wvd.name
  virtual_network_name = azurerm_virtual_network.wvd.name
  address_prefixes     = var.snet_address_space
}

resource "azurerm_network_security_group" "wvd" {
  name                = "nsg-${random_pet.wvd.id}"
  resource_group_name = azurerm_resource_group.wvd.name
  location            = azurerm_resource_group.wvd.location
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "wvd" {
  subnet_id                 = azurerm_subnet.wvd.id
  network_security_group_id = azurerm_network_security_group.wvd.id
}

##########################################
# VIRTUAL NETWORK PEERING
##########################################

# Get resources by type, create spoke vnet peerings
data "azurerm_resources" "vnets" {
  type = "Microsoft.Network/virtualNetworks"

  required_tags = {
    environment = "prod"
    role        = "azops"
  }
}

resource "azurerm_virtual_network_peering" "out" {
  count                        = length(data.azurerm_resources.vnets.resources)
  name                         = "${azurerm_virtual_network.wvd.name}-to-${data.azurerm_resources.vnets.resources[count.index].name}"
  remote_virtual_network_id    = data.azurerm_resources.vnets.resources[count.index].id
  resource_group_name          = azurerm_resource_group.wvd.name
  virtual_network_name         = azurerm_virtual_network.wvd.name
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "in" {
  for_each                     = { for vp in var.vnet_peerings : vp.vnet_name => vp }
  name                         = "${each.value["vnet_name"]}-to-${azurerm_virtual_network.wvd.name}"
  remote_virtual_network_id    = azurerm_virtual_network.wvd.id
  resource_group_name          = each.value["vnet_resource_group_name"]
  virtual_network_name         = each.value["vnet_name"]
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
}

##############################################
# WINDOWS VIRTUAL DESKTOP
##############################################

resource "azurerm_virtual_desktop_host_pool" "wvd" {
  name                     = "hp-${random_pet.wvd.id}"
  resource_group_name      = azurerm_resource_group.wvd.name
  location                 = azurerm_resource_group.wvd.location
  type                     = var.host_pool_type
  load_balancer_type       = var.host_pool_load_balancer_type
  validate_environment     = var.host_pool_validate_environment
  maximum_sessions_allowed = var.host_pool_max_sessions_allowed

  registration_info {
    expiration_date = timeadd(format("%sT00:00:00Z", formatdate("YYYY-MM-DD", timestamp())), "3600m")
  }
}

# Both desktop and remote app application groups are being joined to a single host pool
# however, in production scenario, these should join to separate host pools

resource "azurerm_virtual_desktop_application_group" "wvd" {
  name                = "ag-${random_pet.wvd.id}"
  resource_group_name = azurerm_resource_group.wvd.name
  location            = azurerm_resource_group.wvd.location
  host_pool_id        = azurerm_virtual_desktop_host_pool.wvd.id
  type                = var.desktop_app_group_type
  friendly_name       = upper(random_pet.wvd.id)
}

resource "azurerm_virtual_desktop_workspace" "wvd" {
  name                = "ws-${random_pet.wvd.id}"
  resource_group_name = azurerm_resource_group.wvd.name
  location            = azurerm_resource_group.wvd.location
  friendly_name       = upper(random_pet.wvd.id)
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "wvd" {
  workspace_id         = azurerm_virtual_desktop_workspace.wvd.id
  application_group_id = azurerm_virtual_desktop_application_group.wvd.id
}

##############################################
# WINDOWS VIRTUAL DESKTOP - SESSION HOSTS
##############################################

# Make sure the VM name prefix doesn't exceed 12 characters
locals {
  vm_name = substr(format("vm%s", random_pet.wvd.id), 0, 12)
}

resource "azurerm_network_interface" "wvd" {
  count               = var.vm_count
  name                = "${local.vm_name}-${count.index + 1}_nic"
  resource_group_name = azurerm_resource_group.wvd.name
  location            = azurerm_resource_group.wvd.location

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.wvd.id
    private_ip_address_allocation = "dynamic"
  }

  tags = var.tags
}

resource "azurerm_windows_virtual_machine" "wvd" {
  count               = var.vm_count
  name                = "${local.vm_name}-${count.index + 1}"
  resource_group_name = azurerm_resource_group.wvd.name
  location            = azurerm_resource_group.wvd.location
  size                = var.vm_sku
  admin_username      = var.username
  admin_password      = var.password
  tags                = merge(var.tags, { "role" = "WVDSessionHost" })

  network_interface_ids = [
    element(azurerm_network_interface.wvd.*.id, count.index)
  ]

  os_disk {
    name                 = "${local.vm_name}-${count.index + 1}_osdisk"
    caching              = var.vm_os_disk_caching.caching
    storage_account_type = var.vm_os_disk_caching.storage_account_type
  }

  source_image_reference {
    publisher = var.vm_image.publisher
    offer     = var.vm_image.offer
    sku       = var.vm_image.sku
    version   = var.vm_image.version
  }

  identity {
    type = "SystemAssigned"
  }

  depends_on = [
    azurerm_virtual_network_peering.out,
    azurerm_virtual_network_peering.in
  ]
}

##################################################################
# WINDOWS VIRTUAL DESKTOP - SESSION HOST ANSIBLE CONFIGURATION
##################################################################

# Install WinRM for Ansible
# https://docs.microsoft.com/en-us/azure/virtual-machines/extensions/custom-script-windows
resource "azurerm_virtual_machine_extension" "wvd" {
  count                      = length(azurerm_windows_virtual_machine.wvd)
  name                       = "AnsibleWinRM"
  virtual_machine_id         = azurerm_windows_virtual_machine.wvd[count.index].id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = <<SETTINGS
    {
      "fileUris": [
          "https://raw.githubusercontent.com/ansible/ansible/devel/examples/scripts/ConfigureRemotingForAnsible.ps1"
        ]
    }
  SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
    {
      "commandToExecute": "powershell.exe -Command \"./ConfigureRemotingForAnsible.ps1; exit 0;\""
    }
  PROTECTED_SETTINGS

  depends_on = [
    azurerm_virtual_network_peering.out,
    azurerm_virtual_network_peering.in
  ]
}

################################
# BUILD ANSIBLE INVENTORY
################################

resource "local_file" "wvd" {
  filename = "ansible/inventory"

  content = templatefile("ansible/template-inventory.tpl",
    {
      hosts = zipmap(azurerm_windows_virtual_machine.wvd.*.name, azurerm_network_interface.wvd.*.private_ip_address),
    }
  )
}