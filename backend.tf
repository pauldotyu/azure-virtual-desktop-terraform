terraform {
  backend "remote" {
    organization = "pauldotyu"

    workspaces {
      name = "azure-wvd-terraform"
    }
  }
}