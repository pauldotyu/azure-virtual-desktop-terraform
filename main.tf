terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.83.0"
    }
  }
}

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

# this will peer out to all the virtual networks tagged with a role of azops
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

# this will peer in from all the virtual networks tagged with the role of azops
# this also needs work. right now it is using variables when it should be using the data resource pulled from above;
# howver, the challenge is that the data resource does not return the resrouces' resource group which is required for peering
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
    #expiration_date = timeadd(timestamp(), "648h")
    expiration_date = timeadd(format("%sT00:00:00Z", formatdate("YYYY-MM-DD", timestamp())), "648h")
    # Need to extend this out to the max due to an issue where if the host pool registration token has expired on the Azure side,
    # a null value is returned as Terraform refreshes state. If the value is null, you will need to regen the token from Azure portal or using this command
    # https://github.com/hashicorp/terraform-provider-azurerm/issues/12038
  }
}

# Both desktop and remote app application groups are being joined to a single host pool however, in production scenario, these should join to separate host pools

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

data "azurerm_shared_image" "avd" {
  name                = var.sig_image_name
  gallery_name        = var.sig_name
  resource_group_name = var.sig_resource_group_name
}

data "azurerm_shared_image_version" "avd" {
  name                = "latest"
  image_name          = var.sig_image_name
  gallery_name        = var.sig_name
  resource_group_name = var.sig_resource_group_name
}

resource "random_string" "avd" {
  length  = 3
  upper   = true
  number  = true
  lower   = false
  special = false

  # # this ensures that we get a fresh set of VMs on every run
  # keepers = {
  #   timestamp = timestamp()
  # }
}

locals {
  # NOTE: this algorithm works for images that were built using Azure Image Builder as they produce unique image versions that look like this: 0.24926.27922
  # Logic to build VM name prefix:
  # 1. Get the image version
  # 2. Grab the id
  # 3. Split the id into an array using slash
  # 4. Reverse the order of the elements in the array
  # 5. Take the first element
  # 6. Remove the dot
  # vm_name_prefix = replace(element(reverse(split("/", data.azurerm_shared_image_version.avd.id)), 0), ".", "")
  # vm_image_name  = element(reverse(split("/", data.azurerm_shared_image_version.avd.id)), 2)

  vm_name_prefix = format("VM%s%s", upper(substr(random_pet.avd.id, 0, 7)), random_string.avd.result)
  vm_image_name  = var.sig_image_name #var.vm_image.sku
}

resource "azurerm_network_interface" "avd" {
  count               = var.vm_count
  name                = "${local.vm_name_prefix}-${count.index + 1}_nic"
  resource_group_name = azurerm_resource_group.avd.name
  location            = azurerm_resource_group.avd.location

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.avd.id
    private_ip_address_allocation = "dynamic"
  }

  # lifecycle {
  #   create_before_destroy = true
  # }

  tags = var.tags
}

resource "azurerm_windows_virtual_machine" "avd" {
  count                    = var.vm_count
  name                     = "${local.vm_name_prefix}-${count.index + 1}"
  resource_group_name      = azurerm_resource_group.avd.name
  location                 = azurerm_resource_group.avd.location
  size                     = var.vm_sku
  admin_username           = var.username
  admin_password           = var.password
  enable_automatic_updates = false
  patch_mode               = "Manual"
  license_type             = "Windows_Client"
  timezone                 = "Pacific Standard Time"

  tags = merge(var.tags, {
    "role"  = "AVDSessionHost"
    "image" = local.vm_image_name
  })

  network_interface_ids = [
    element(azurerm_network_interface.avd.*.id, count.index)
  ]

  os_disk {
    name                 = "${local.vm_name_prefix}-${count.index + 1}_osdisk"
    caching              = var.vm_os_disk_caching.caching
    storage_account_type = var.vm_os_disk_caching.storage_account_type
  }

  # source_image_reference {
  #   publisher = var.vm_image.publisher
  #   offer     = var.vm_image.offer
  #   sku       = var.vm_image.sku
  #   version   = var.vm_image.version
  # }

  #source_image_id = data.azurerm_shared_image.avd.id
  source_image_id = data.azurerm_shared_image_version.avd.id

  identity {
    type = "SystemAssigned"
  }

  # lifecycle {
  #   create_before_destroy = true
  # }

  depends_on = [
    azurerm_virtual_network_peering.out,
    azurerm_virtual_network_peering.in
  ]
}

###############################################################################################
# AZURE VIRTUAL DESKTOP - SESSION HOST ANSIBLE CONFIGURATION  - IF USING ANSIBLE TO CONFIGURE
###############################################################################################

# Install WinRM for Ansible
# https://docs.microsoft.com/en-us/azure/virtual-machines/extensions/custom-script-windows
resource "azurerm_virtual_machine_extension" "avd" {
  count                      = var.configure_using_ansible ? length(azurerm_windows_virtual_machine.avd) : 0
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
      "commandToExecute": "powershell.exe -ExecutionPolicy Bypass -Command \"./ConfigureRemotingForAnsible.ps1 -EnableCredSSP -DisableBasicAuth -Verbose; exit 0;\""
    }
  PROTECTED_SETTINGS

  # lifecycle {
  #   create_before_destroy = true
  # }

  depends_on = [
    azurerm_virtual_network_peering.out,
    azurerm_virtual_network_peering.in
  ]
}

############################################################
# BUILD ANSIBLE INVENTORY - IF USING ANSIBLE TO CONFIGURE
###########################################################

resource "local_file" "avd" {
  count    = var.configure_using_ansible ? 1 : 0
  filename = "ansible/inventory"
  content = templatefile("ansible/template-inventory.tpl",
    {
      hosts = zipmap(azurerm_windows_virtual_machine.avd.*.name, azurerm_network_interface.avd.*.private_ip_address),
    }
  )
}

#############################################################
# DOMAIN JOIN EXTENSION - IF NOT USING ANSIBLE TO CONFIGURE
#############################################################

resource "azurerm_virtual_machine_extension" "domain_join" {
  count                      = var.configure_using_ansible ? 0 : var.vm_count
  name                       = "${local.vm_name_prefix}-${count.index + 1}-domainJoin"
  virtual_machine_id         = azurerm_windows_virtual_machine.avd.*.id[count.index]
  publisher                  = "Microsoft.Compute"
  type                       = "JsonADDomainExtension"
  type_handler_version       = "1.3"
  auto_upgrade_minor_version = true

  settings = <<SETTINGS
    {
      "Name": "${var.domain_name}",
      "OUPath": "${var.domain_ou_path}",
      "User": "${var.domain_username}",
      "Restart": "true",
      "Options": "3"
    }
SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
    {
      "Password": "${var.domain_password}"
    }
PROTECTED_SETTINGS

  lifecycle {
    # create_before_destroy = true
    ignore_changes = [settings, protected_settings]
  }

  depends_on = [
    azurerm_virtual_network_peering.out,
    azurerm_virtual_network_peering.in
  ]
}

###################################################################
# AVD AGENT INSTALL EXTENSION - IF NOT USING ANSIBLE TO CONFIGURE
###################################################################

resource "azurerm_virtual_machine_extension" "agent_install" {
  count                      = var.configure_using_ansible ? 0 : var.vm_count
  name                       = "${local.vm_name_prefix}-${count.index + 1}-avd_dsc"
  virtual_machine_id         = azurerm_windows_virtual_machine.avd.*.id[count.index]
  publisher                  = "Microsoft.Powershell"
  type                       = "DSC"
  type_handler_version       = "2.73"
  auto_upgrade_minor_version = true

  settings = <<-SETTINGS
    {
      "modulesUrl": "https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_3-10-2021.zip",
      "configurationFunction": "Configuration.ps1\\AddSessionHost",
      "properties": {
        "HostPoolName":"${azurerm_virtual_desktop_host_pool.avd.name}"
      }
    }
SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
  {
    "properties": {
      "registrationInfoToken": "${azurerm_virtual_desktop_host_pool.avd.registration_info[0].token}"
    }
  }
PROTECTED_SETTINGS

  lifecycle {
    # create_before_destroy = true
    ignore_changes = [settings, protected_settings]
  }

  depends_on = [
    azurerm_virtual_machine_extension.domain_join,
    azurerm_virtual_desktop_host_pool.avd
  ]
}
