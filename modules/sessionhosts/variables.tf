variable "subnet_id" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "tags" {
  type = map(any)
}

variable "host_pool_name" {
  type = string
}

variable "host_pool_token" {
  type = string
}

variable "session_host_status" {
  type = string
}

variable "vm_name_prefix" {
  type = string
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

variable "vm_os_disk_caching" {
  type = object({
    caching              = string
    storage_account_type = string
  })
  description = "Virtual machine OS disk caching"
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

variable "vm_custom_image_id" {
  type = string
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
