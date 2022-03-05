variable "location" {
  type = string
}

variable "desktopvirtualization_location" {
  type        = string
  description = "DesktopVirtualization resource location can be different from session host region. As of 2/28/22, this resource is only available in the following regions: 'uksouth,ukwest,canadaeast,canadacentral,northeurope,westeurope,eastus,eastus2,westus,westus2,northcentralus,southcentralus,westcentralus,centralus'"
}

variable "netops_subscription_id" {
  type        = string
  description = "Adding a new provider here as some AVD deployments may need to peer with hub vnets in a different subscription. If the hub network is in the same subscription as the AVD deployment, then set the AVD subscription ID here."
}

variable "netops_role_tag_value" {
  type        = string
  description = "Virtual network peerings will be made based on a \"role\" tags on the resource. Any resource virtual network resources with this value will peered."
}

variable "devops_subscription_id" {
  type        = string
  description = "Adding a new provider here as some AVD deployments may need to peer with hub vnets in a different subscription. If the hub network is in the same subscription as the AVD deployment, then set the AVD subscription ID here."
}

variable "devops_role_tag_value" {
  type        = string
  description = "Virtual network peerings will be made based on a \"role\" tags on the resource. Any resource virtual network resources with this value will peered."
}

variable "tags" {
  type = map(any)
}

variable "vnet_address_space" {
  type = list(string)
}

variable "vnet_custom_dns_servers" {
  type = list(string)
}

variable "snet_address_space" {
  type = list(string)
}

variable "host_pool_type" {
  type    = string
  default = "Pooled"
}

variable "host_pool_load_balancer_type" {
  type    = string
  default = "DepthFirst"
}

variable "host_pool_validate_environment" {
  type    = bool
  default = false
}

variable "host_pool_max_sessions_allowed" {
  type    = number
  default = 999999
}

variable "desktop_app_group_type" {
  type    = string
  default = "Desktop"
  validation {
    condition = can(index([
      "Desktop",
      "RemoteApp"
    ], var.desktop_app_group_type) >= 0)
    error_message = "Pick desktop application group or remote application group but not both."
  }
}

variable "aad_group_name" {
  type        = string
  description = "Azure AD Security-Enabled Group to be assigned to the Desktop Application Group"
}

variable "vm_count" {
  type    = number
  default = 1
}

variable "vm_sku" {
  type        = string
  description = "Virtual machine SKU"
}

variable "vm_username" {
  type = string
}

variable "vm_password" {
  type      = string
  sensitive = true
}

variable "vm_marketplace_image" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  description = "Virtual machine image - Use 'az vm image' command to find your image"
}

variable "vm_os_disk_caching" {
  type = object({
    caching              = string
    storage_account_type = string
  })
  description = "Virtual machine OS disk caching"
}

variable "acg_image_name" {
  type        = string
  description = "Image definition name"
}

variable "acg_name" {
  type        = string
  description = "Shared Image Gallery name"
}

variable "acg_resource_group_name" {
  type        = string
  description = "Shared Image Gallery resource group name"
}

variable "configure_using_ansible" {
  type        = bool
  description = "Set this to true if you want to use Ansible to perform the domain join and session host agent installation"
  default     = false
}

####################################################
# The variables listed below are only needed
# if not using Ansible to configure session hosts
####################################################
variable "domain_name" {
  type    = string
  default = ""
}

variable "domain_ou_path" {
  type    = string
  default = ""
}

variable "domain_username" {
  type    = string
  default = ""
}

variable "domain_password" {
  type    = string
  default = ""
}


variable "session_hosts" {
  type = list(object({
    batch             = string
    status            = string
    count             = number
    acg_image_version = string
  }))
}
