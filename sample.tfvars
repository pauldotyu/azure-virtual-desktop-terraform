location = "westus2"
tags = {
  "po-number"          = "zzz"
  "environment"        = "prod"
  "mission"            = "administrative"
  "protection-level"   = "p1"
  "availability-level" = "a1"
}

# Virtual Networking
vnet_address_space = ["10.21.17.0/28"]
vnet_custom_dns_servers = [
  "10.21.0.4",
  "10.21.0.5"
]
vnet_peerings = [
  {
    vnet_resource_group_name = "rg-aadds"
    vnet_name                = "vn-aadds"
  },
  {
    vnet_resource_group_name = "rg-devops"
    vnet_name                = "vn-devops"
  }
]
snet_address_space = ["10.21.17.0/28"]

# VM Size
vm_count = 1
vm_sku   = "Standard_D4s_v3"
vm_os_disk_caching = {
  caching              = "ReadWrite"
  storage_account_type = "Standard_LRS"
}

# VM Image Definition
vm_image = {
  publisher = "microsoftwindowsdesktop"
  offer     = "office-365"
  sku       = "20h2-evd-o365pp"
  version   = "latest"
}

# Use either this or the image source above - still testing
sig_image_name          = "avd-ethicalbedbug"
sig_name                = "sigethicalbedbug"
sig_resource_group_name = "rg-ethicalbedbug"