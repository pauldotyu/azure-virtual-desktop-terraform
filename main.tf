provider "azurerm" {
  features {}
}

resource "random_pet" "avd" {
  length    = 2
  separator = ""
}

resource "azurerm_resource_group" "avd" {
  name     = "rg-${random_pet.avd.id}"
  location = var.location
  tags     = var.tags
}

##############################################
# VIRTUAL NETWORKING
##############################################

resource "azurerm_virtual_network" "avd" {
  name                = "vn-${random_pet.avd.id}"
  resource_group_name = azurerm_resource_group.avd.name
  location            = azurerm_resource_group.avd.location
  tags                = var.tags
  address_space       = var.vnet_address_space
  dns_servers         = var.vnet_custom_dns_servers
}

resource "azurerm_subnet" "avd" {
  name                 = "sn-${random_pet.avd.id}"
  resource_group_name  = azurerm_resource_group.avd.name
  virtual_network_name = azurerm_virtual_network.avd.name
  address_prefixes     = var.snet_address_space
}

resource "azurerm_network_security_group" "avd" {
  name                = "nsg-${random_pet.avd.id}"
  resource_group_name = azurerm_resource_group.avd.name
  location            = azurerm_resource_group.avd.location
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "avd" {
  subnet_id                 = azurerm_subnet.avd.id
  network_security_group_id = azurerm_network_security_group.avd.id
}

##########################################
# VIRTUAL NETWORK PEERING
##########################################

# Get resources by type, create vnet peerings
data "azurerm_resources" "vnets" {
  type = "Microsoft.Network/virtualNetworks"

  required_tags = {
    role = "azops"
  }
}

// this will peer out to all the virtual networks tagged with a role of azops
resource "azurerm_virtual_network_peering" "out" {
  count                        = length(data.azurerm_resources.vnets.resources)
  name                         = "${azurerm_virtual_network.avd.name}-to-${data.azurerm_resources.vnets.resources[count.index].name}"
  remote_virtual_network_id    = data.azurerm_resources.vnets.resources[count.index].id
  resource_group_name          = azurerm_resource_group.avd.name
  virtual_network_name         = azurerm_virtual_network.avd.name
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

// this will peer in from all the virtual networks tagged with the role of azops
// this also needs work. right now it is using variables when it should be using the data resource pulled from above; howver, the challenge is that the data resource does not return the resrouces' resource group which is required for peering
resource "azurerm_virtual_network_peering" "in" {
  for_each                     = { for vp in var.vnet_peerings : vp.vnet_name => vp }
  name                         = "${each.value["vnet_name"]}-to-${azurerm_virtual_network.avd.name}"
  remote_virtual_network_id    = azurerm_virtual_network.avd.id
  resource_group_name          = each.value["vnet_resource_group_name"]
  virtual_network_name         = each.value["vnet_name"]
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
}

##############################################
# AZURE VIRTUAL DESKTOP
##############################################

resource "azurerm_virtual_desktop_host_pool" "avd" {
  name                     = "hp-${random_pet.avd.id}"
  resource_group_name      = azurerm_resource_group.avd.name
  location                 = azurerm_resource_group.avd.location
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

resource "azurerm_virtual_desktop_application_group" "avd" {
  name                = "ag-${random_pet.avd.id}"
  resource_group_name = azurerm_resource_group.avd.name
  location            = azurerm_resource_group.avd.location
  host_pool_id        = azurerm_virtual_desktop_host_pool.avd.id
  type                = var.desktop_app_group_type
  friendly_name       = upper(random_pet.avd.id)
}

resource "azurerm_virtual_desktop_workspace" "avd" {
  name                = "ws-${random_pet.avd.id}"
  resource_group_name = azurerm_resource_group.avd.name
  location            = azurerm_resource_group.avd.location
  friendly_name       = upper(random_pet.avd.id)
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "avd" {
  workspace_id         = azurerm_virtual_desktop_workspace.avd.id
  application_group_id = azurerm_virtual_desktop_application_group.avd.id
}

##############################################
# AZURE VIRTUAL DESKTOP - SESSION HOSTS
##############################################

# Make sure the VM name prefix doesn't exceed 12 characters
locals {
  vm_name = substr(format("vm%s", random_pet.avd.id), 0, 12)
}

resource "azurerm_network_interface" "avd" {
  count               = var.vm_count
  name                = "${local.vm_name}-${count.index + 1}_nic"
  resource_group_name = azurerm_resource_group.avd.name
  location            = azurerm_resource_group.avd.location

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.avd.id
    private_ip_address_allocation = "dynamic"
  }

  tags = var.tags
}

# data "azurerm_shared_image" "avd" {
#   name                = var.sig_image_name
#   gallery_name        = var.sig_name
#   resource_group_name = var.sig_resource_group_name
# }

# data "azurerm_shared_image_version" "avd" {
#   name                = "latest"
#   image_name          = var.sig_image_name
#   gallery_name        = var.sig_name
#   resource_group_name = var.sig_resource_group_name
# }

data "azurerm_shared_image" "avd" {
  name                = "avd-ethicalbedbug"
  gallery_name        = "sigethicalbedbug"
  resource_group_name = "rg-ethicalbedbug"
}


resource "azurerm_windows_virtual_machine" "avd" {
  count               = var.vm_count
  name                = "${local.vm_name}-${count.index + 1}"
  resource_group_name = azurerm_resource_group.avd.name
  location            = azurerm_resource_group.avd.location
  size                = var.vm_sku
  admin_username      = var.username
  admin_password      = var.password
  tags                = merge(var.tags, { "role" = "AVDSessionHost" })

  network_interface_ids = [
    element(azurerm_network_interface.avd.*.id, count.index)
  ]

  os_disk {
    name                 = "${local.vm_name}-${count.index + 1}_osdisk"
    caching              = var.vm_os_disk_caching.caching
    storage_account_type = var.vm_os_disk_caching.storage_account_type
  }

  source_image_id = data.azurerm_shared_image.avd.id

  # source_image_reference {
  #   publisher = var.vm_image.publisher
  #   offer     = var.vm_image.offer
  #   sku       = var.vm_image.sku
  #   version   = var.vm_image.version
  # }

  #source_image_id = data.azurerm_shared_image_version.avd.id

  identity {
    type = "SystemAssigned"
  }

  depends_on = [
    azurerm_virtual_network_peering.out,
    azurerm_virtual_network_peering.in
  ]
}

##################################################################
# AZURE VIRTUAL DESKTOP - SESSION HOST ANSIBLE CONFIGURATION
##################################################################

# Install WinRM for Ansible
# https://docs.microsoft.com/en-us/azure/virtual-machines/extensions/custom-script-windows
resource "azurerm_virtual_machine_extension" "avd" {
  count                      = length(azurerm_windows_virtual_machine.avd)
  name                       = "AnsibleWinRM"
  virtual_machine_id         = azurerm_windows_virtual_machine.avd[count.index].id
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
      "commandToExecute": "powershell.exe -ExecutionPolicy Bypass -Command \"./ConfigureRemotingForAnsible.ps1; exit 0;\""
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

resource "local_file" "avd" {
  filename = "ansible/inventory"

  content = templatefile("ansible/template-inventory.tpl",
    {
      hosts = zipmap(azurerm_windows_virtual_machine.avd.*.name, azurerm_network_interface.avd.*.private_ip_address),
    }
  )
}