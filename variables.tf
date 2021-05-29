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
  default = "BreadthFirst"
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

variable "username" {
  type = string
}

variable "password" {
  type      = string
  sensitive = true
}

variable "vm_image" {
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
