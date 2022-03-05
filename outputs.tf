output "registration_token" {
  value     = azurerm_virtual_desktop_host_pool_registration_info.avd.token
  sensitive = true
}