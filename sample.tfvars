location = "westus2"
tags = {
  "po-number"          = "zzz"
  "environment"        = "prod"
  "mission"            = "administrative"
  "protection-level"   = "p1"
  "availability-level" = "a1"
}

# Virtual Networking
vnet_address_space = ["10.103.1.0/24"]
snet_address_space = ["10.103.1.0/25"]
vnet_custom_dns_servers = [
  "10.102.2.4"
]
vnet_peerings = [
  {
    vnet_resource_group_name = "rg-adds"
    vnet_name                = "vn-adds"
  },
  {
    vnet_resource_group_name = "rg-devops"
    vnet_name                = "vn-devops"
  }
]

# VM Size
vm_count = 1
vm_sku   = "Standard_D4s_v3"
vm_os_disk_caching = {
  caching              = "ReadWrite"
  storage_account_type = "Standard_LRS"
}

# VM Image Definition
vm_marketplace_image = {
  publisher = "microsoftwindowsdesktop"
  offer     = "office-365"
  sku       = "win11-21h2-avd-m365"
  version   = "latest"
}

host_pool_token_expiration = "2021-12-03T00:00:00Z"

sig_resource_group_name = "rg-cheesehead"
sig_name                = "sigcheesehead"
sig_image_name          = "windows11-m365"

session_hosts = [
  {
    batch             = "002"
    sig_image_version = "0.20211107.4"
    count             = 1
    status            = "Production"
  },
]