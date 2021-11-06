variable "location" {
  type = string
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

variable "vnet_peerings" {
  type = list(object({
    vnet_resource_group_name = string
    vnet_name                = string
  }))
  description = "List of remote virtual networks to peer with"
}

variable "sig_image_name" {
  type        = string
  description = "Image definition name"
}

variable "sig_name" {
  type        = string
  description = "Shared Image Gallery name"
}

variable "sig_resource_group_name" {
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
    sig_image_version = string
  }))
}

variable "host_pool_token_expiration" {
  type = string
}