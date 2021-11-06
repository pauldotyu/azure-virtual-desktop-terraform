
##############################################
# AZURE VIRTUAL DESKTOP - SESSION HOSTS
##############################################

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

  vm_name_prefix = format("%s%s-%s", var.vm_name_prefix, random_string.avd.result, var.session_host_batch)
}

resource "azurerm_network_interface" "avd" {
  count               = var.vm_count
  name                = "${local.vm_name_prefix}-${count.index + 1}_nic"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.subnet_id
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
  resource_group_name      = var.resource_group_name
  location                 = var.location
  size                     = var.vm_sku
  admin_username           = var.vm_username
  admin_password           = var.vm_password
  enable_automatic_updates = false
  patch_mode               = "Manual"
  license_type             = "Windows_Client"
  timezone                 = "Pacific Standard Time"

  tags = merge(var.tags, {
    "role"   = "AVDSessionHost"
    "status" = var.session_host_status
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
  #   publisher = var.vm_marketplace_mage.publisher
  #   offer     = var.vm_marketplace_image.offer
  #   sku       = var.vm_marketplace_image.sku
  #   version   = var.vm_marketplace_image.version
  # }

  #source_image_id = data.azurerm_shared_image.avd.id
  source_image_id = var.vm_custom_image_id

  identity {
    type = "SystemAssigned"
  }

  # lifecycle {
  #   create_before_destroy = true
  # }
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
  name                       = "${local.vm_name_prefix}-${count.index + 1}-DomainJoin"
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
}

###################################################################
# AVD AGENT INSTALL EXTENSION - IF NOT USING ANSIBLE TO CONFIGURE
###################################################################

resource "azurerm_virtual_machine_extension" "rdagent_install" {
  count                      = var.configure_using_ansible ? 0 : var.vm_count
  name                       = "${local.vm_name_prefix}-${count.index + 1}-RDAgentInstall"
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
        "HostPoolName":"${var.host_pool_name}"
      }
    }
SETTINGS

  protected_settings = <<PROTECTED_SETTINGS
  {
    "properties": {
      "registrationInfoToken": "${var.host_pool_token}"
    }
  }
PROTECTED_SETTINGS

  lifecycle {
    # create_before_destroy = true
    ignore_changes = [settings, protected_settings]
  }

  depends_on = [
    azurerm_virtual_machine_extension.domain_join,
  ]
}
