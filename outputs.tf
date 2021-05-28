output "registration_token" {
  value     = azurerm_virtual_desktop_host_pool.wvd.registration_info[0].token
  sensitive = true
}