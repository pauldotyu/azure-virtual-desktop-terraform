location                       = "westus2"
desktopvirtualization_location = "westus2"

tags = {
  "po-number"          = "zzz"
  "environment"        = "dev"
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

acg_resource_group_name = "rg-cheesehead"
acg_name                = "sigcheesehead"
acg_image_name          = "windows11-m365"

session_hosts = [
  {
    batch             = "002"
    acg_image_version = "0.20211107.4"
    count             = 1
    status            = "Production"
  },
]

publisher = "contoso"
offer     = "windows"
sku       = "avd"

netops_subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
netops_role_tag_value  = "azops"

devops_subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
devops_role_tag_value  = "azops"

aad_group_name = "sg-Sales and Marketing"