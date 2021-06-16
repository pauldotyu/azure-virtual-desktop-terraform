terraform {
  backend "remote" {
    organization = "pauldotyu"

    workspaces {
      name = "azure-avd-terraform"
    }
  }
}