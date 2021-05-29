# azure-wvd-terraform

This basic implementation of Windows Virtual Desktop in Azure will be deployed using Terraform for Azure resource provisioning, Ansible for Windows configuration, and GitHub Actions for automation.

This only repo focuses on deploying the resources in the Windows Virtual Desktop resource group (in the middle of the diagram below).

![Architecture](images/architecture.png)

## Prerequisites

To deploy the demo WVD solution within your environment you will need to have the following resources in place:

1. Windows Active Directory Domain Services or [Azure Active Directory Domain Services](https://azure.microsoft.com/en-us/services/active-directory-ds/) deployed in Azure.
1. [GitHub Account](https://github.com/join) so that you can [clone](https://docs.github.com/en/github/creating-cloning-and-archiving-repositories/cloning-a-repository-from-github/cloning-a-repository) this repo or [create a new repo from this template](https://docs.github.com/en/github/creating-cloning-and-archiving-repositories/creating-a-repository-on-github/creating-a-repository-from-a-template).
1. [Ubuntu Virtual Machine](https://docs.microsoft.com/en-us/azure/virtual-machines/linux/quick-create-portal) deployed in Azure with the following software installed:
    1. [GitHub Actions self-hosted runner](https://docs.github.com/en/actions/hosting-your-own-runners/about-self-hosted-runners)
    1. [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt)
    1. [Terraform](https://www.terraform.io/docs/cli/install/apt.html)
    1. [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html#installing-and-upgrading-ansible-with-pip)
    1. Unzip 
    1. [Node.js](https://nodejs.org/en/download/package-manager/#debian-and-ubuntu-based-linux-distributions)
    1. [npm](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm)

## Overview

The Terraform configuration will generate a random "pet name" to be used in naming all your resources. This is fun for a demo, but can change this as needed.

All resources will be named using a 2-4 character code based on the Azure service as the name prefix followed by a dash and the random pet name. Again, if you don't like these names, then change it.

This deployment assumes you have full control of your subscription and access to create virtual network peerings between the WVD virtual network and AADDS and DevOps virtual networks. If you don't have this level of access, you'll need to re-evaluate how much you can automate. I am working out of my sandbox Azure subscription and do not have limitations you may run into in a production scenario.

The following following resources will be deployed by this repo:

- [Azure Resource Group](https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-portal)
- [Azure Virtual Network](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-networks-overview) with a single subnet and [Network Security Group](https://docs.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview) wrapped around it
    > The virtual network will also have [custom DNS configured](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-networks-name-resolution-for-vms-and-role-instances) so that your WVD session host VM can communicate with the domain controller when it comes time to domain join.
- [Azure Virtual Network peerings](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-network-manage-peering) to and from WVD virtual network for AADDS and DevOps
- [Windows Virtual Desktop Host Pool](https://docs.microsoft.com/en-us/azure/virtual-desktop/create-host-pools-azure-marketplace) and the host pool registration token will be exported as an output in the Terraform configuration
- [Windows Virtual Desktop Application Group](https://docs.microsoft.com/en-us/azure/virtual-desktop/manage-app-groups)
- Windows Virtual Desktop Workspace
- [Windows Virtual Machine(s)](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/quick-create-portal) with a [Custom Script Extension](https://docs.microsoft.com/en-us/azure/virtual-machines/extensions/custom-script-windows) to configure [WinRM for Ansible](https://docs.ansible.com/ansible/latest/user_guide/windows_winrm.html)
- Local inventory file with host name and IP to run the Ansible playbook against

## Terraform Setup

Terraform requires you to manage state files. You can opt to store remote state in [Azure Storage Account](https://docs.microsoft.com/en-us/azure/developer/terraform/store-state-in-azure-storage) or in [Terraform Cloud](https://www.terraform.io/cloud). Whichever solution you chose, be sure to update the your [`backend.tf`](backend.tf) file to reflect your remote state solution. This repo uses Terraform Cloud and for the GitHub Action to work a Terraform Cloud account, you will need to create an [API token](https://www.terraform.io/docs/cloud/users-teams-organizations/users.html#api-tokens) and save it as a secret in [GitHub Secrets](https://docs.github.com/en/actions/reference/encrypted-secrets#creating-encrypted-secrets-for-a-repository) named `TF_API_TOKEN`.

This repo uses Terraform Cloud purely for storing remote state files. You have the option of also running your Terraform script on Terraform Cloud infrastructure, but I opted to run it locally on the self-hosted runner. This will enable us to use the Ansible inventory file when it comes time to call the Ansible playbook in our GitHub Action. This means we will need to use an [Azure Service Principal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/service_principal_client_secret) and export the secrets prior to running each Terraform command. Once you have the secret values, enter them in GitHub Secrets using the following names (You could name them anything you want but you'll need to make sure they are updated in the [`terraform.yml`](./github/workflows/terraform.yml) workflow file).

- `ARM_CLIENT_ID`
- `ARM_CLIENT_SECRET`
- `ARM_SUBSCRIPTION_ID`
- `ARM_TENANT_ID`

This repo also aims to use variables as much as possible for re-usability. The variable definitions can be found in the [`variables.tf`](variables.tf) file. The vaules for each deployment can be maintained in a `*.tfvars` file. I've included a [`sample.tfvars`](sample.tfvars) file so you can update as needed based on what is deployed in your environment and preferences.

To run the Terrafrom script locally, take a look at the [`terraform.yml`](./github/workflows/terraform.yml) workflow file. There you'll find a `terraform plan` and `terraform apply` command with all the arguments you'll need.

> NOTE: If you decide to change the name of the sample.tfvars file, you'll also need to update the filename in the workflow.

## Ansible Setup

The `site.yml` [Ansible Playbook](https://docs.ansible.com/ansible/latest/user_guide/playbooks.html) found in this repo relies on a few variables needed to connect to your VM and domain join them. Rather then saving credentials to the repo (never a good thing) we'll use `ansible-vault` to encrypt contents leveraging [Ansible Vault](https://docs.ansible.com/ansible/latest/user_guide/vault.html). The encrypted vault will then be commited to the repo as `secrets.yml`. The `secrets.yml` file in this repo is my secrets file so you'll need to overwrite it with your own.

Let's start by creating a vault file:

```sh
ansible-vault create secrets.yml
```

You will be prompted for a password. Go ahead and enter a super-secret password.

> NOTE: You will also need to save the vault password as a GitHub repo Secret named `ANSIBLE_VAULT_PASSWORD` for the GitHub Action workflow to use.

After the vault password has been set, a VI editor will open. Be sure to hit the `i` key to put yourself in `insert` mode and enter the following:

```text
ansible_user: <YOUR_VM_USERNAME>
ansible_password: <YOUR_VM_PASSWORD>
dns_domain_name: <YOUR_DOMAIN_NAME>
domain_admin_user: <YOUR_DOMAIN_USERNAME>
domain_admin_password: <YOUR_DOMAIN_PASSWORD>
domain_ou_path: <YOUR_DOMAIN_DISTINGUISHED_OU_PATH>
```

> Save the file using the following command `:wq`

If you need to update the vault, you can run the following command to edit the file:

```sh
ansible-vault edit secrets.yml
```

With the file saved to the repo, the GitHub Action workflow will use the `ANSIBLE_VAULT_PASSWORD` to unlock the vault as the Ansible playbook is run.

To view the Ansible playbook command, take a look at the [`terraform.yml`](./github/workflows/terraform.yml) workflow file and look for the Ansible Playbook task.

More on Ansible Secrets here:

- [Encrypting content with Ansible Vault](https://docs.ansible.com/ansible/latest/user_guide/vault.html)
- [Handling secrets in your Ansible playbooks](https://www.redhat.com/sysadmin/ansible-playbooks-secrets)

### GitHub Action

If you configured all the proper secrets (listed in steps above) you should see an Action running each time you do a push or pull request into the main branch.

Now, go watch it run and have fun!!

## Clean Up

Then you are ready to clean things up, you can run the following command.

```sh
terraform destroy -var-file=sample.tfvars -var=username=user -var=password=pass
```
