terraform {
  backend "remote" {
    organization = "contosouniversity"

    workspaces {
      name = "azure-wvd-terraform"
    }
  }
}