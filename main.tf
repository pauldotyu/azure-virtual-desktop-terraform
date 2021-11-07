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
    #expiration_date = timeadd(timestamp(), "2h")
    #expiration_date = timeadd(format("%sT00:00:00Z", formatdate("YYYY-MM-DD", timestamp())), "648h")
    # Need to extend this out to the max due to an issue where if the host pool registration token has expired on the Azure side,
    # a null value is returned as Terraform refreshes state. If the value is null, you will need to regen the token from Azure portal or using this command
    # https://github.com/hashicorp/terraform-provider-azurerm/issues/12038
    # This can also cause issues when attempting to re-run the build once all session hosts have been deployed
    # https://github.com/hashicorp/terraform-provider-azurerm/issues/12038
    # As a workaround, we can manually set the expiration date to ensure it will not change on every run.
    expiration_date = var.host_pool_token_expiration
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


# Build session hosts
data "azurerm_shared_image" "avd" {
  name                = var.sig_image_name
  gallery_name        = var.sig_name
  resource_group_name = var.sig_resource_group_name
}

module "sessionhosts" {
  source = "./modules/sessionhosts"

  for_each = { for sh in var.session_hosts : sh.batch => sh }

  resource_group_name     = azurerm_resource_group.avd.name
  location                = azurerm_resource_group.avd.location
  subnet_id               = azurerm_subnet.avd.id
  tags                    = var.tags
  host_pool_name          = azurerm_virtual_desktop_host_pool.avd.name
  host_pool_token         = azurerm_virtual_desktop_host_pool.avd.registration_info[0].token
  session_host_status     = each.value["status"]
  vm_name_prefix          = format("%s-%s", upper(substr(random_pet.avd.id, 0, 8)), each.value["batch"])
  vm_count                = each.value["count"]
  vm_sku                  = var.vm_sku
  vm_username             = var.vm_username
  vm_password             = var.vm_password
  vm_os_disk_caching      = var.vm_os_disk_caching
  vm_marketplace_image    = null
  vm_custom_image_id      = "${data.azurerm_shared_image.avd.id}/versions/${each.value["sig_image_version"]}"
  configure_using_ansible = var.configure_using_ansible
  domain_name             = var.domain_name
  domain_ou_path          = var.domain_ou_path
  domain_username         = var.domain_username
  domain_password         = var.domain_password

  depends_on = [
    azurerm_virtual_desktop_host_pool.avd,
    azurerm_virtual_network_peering.out,
    azurerm_virtual_network_peering.in
  ]
}
