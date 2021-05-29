# azure-wvd-terraform

This basic implementation of Windows Virtual Desktop in Azure will be deployed using Terraform for Azure resource provisioning, Ansible for Windows configuration, and GitHub Actions for automation.

Only the resources resources in the Windows Virtual Desktop Resource Group depicted in the middle of the diagram below, are within scope for this deployment.

![Architecture](images/architecture.png)

## Prerequisites

To deploy the demo WVD solution within your environment, you will need to have the following resources in place:

1. A Windows Active Directory Domain Services Domain Controller or [Azure Active Directory Domain Services](https://azure.microsoft.com/en-us/services/active-directory-ds/) deployed in Azure.
1. A [GitHub Account](https://github.com/join) to [clone](https://docs.github.com/en/github/creating-cloning-and-archiving-repositories/cloning-a-repository-from-github/cloning-a-repository) this repo or [create a new repo from this template](https://docs.github.com/en/github/creating-cloning-and-archiving-repositories/creating-a-repository-on-github/creating-a-repository-from-a-template).
1. A [Ubuntu Virtual Machine](https://docs.microsoft.com/en-us/azure/virtual-machines/linux/quick-create-portal) deployed in Azure with the following tools installed:
    - [GitHub Actions self-hosted runner](https://docs.github.com/en/actions/hosting-your-own-runners/about-self-hosted-runners)
    - [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt)
    - [Terraform](https://www.terraform.io/docs/cli/install/apt.html)
    - [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html#installing-and-upgrading-ansible-with-pip)
    - Unzip 
        > `sudo apt-get install unzip` 
    - [Node.js](https://nodejs.org/en/download/package-manager/#debian-and-ubuntu-based-linux-distributions)
    - [npm](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm)

## Overview

The Terraform configuration will generate a "random pet name" to be used in naming Azure resources. This is fun for a demo, but you can change this as needed.

All Azure resources will be named using a naming convention of 2-4 character code based on the Azure service as the name prefix followed by a dash and the "random pet name". Again, if you don't like these names, you should change it.

This deployment also assumes you have full control of your subscription and have the proper permissions to create two sets of Azure Virtual Network Peerings; one between the WVD Virtual Network and AADDS Virtual Network and another between the WVD Virtual Network and DevOps virtual networks. If you don't have this level of access, you'll need to re-evaluate how much of this you can automate. I am working out of my sandbox Azure subscription and do not have limitations which you may run into in a production scenario.

The following resources will be deployed using Terraform:

- [Azure Resource Group](https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-portal)
- [Azure Virtual Network](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-networks-overview) with a single subnet and [Network Security Group](https://docs.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview) wrapped around it
    > The virtual network will also have [custom DNS configured](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-networks-name-resolution-for-vms-and-role-instances) so that your WVD session host VM can communicate with the domain controller when it comes time to domain join.
- [Azure Virtual Network peerings](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-network-manage-peering) to and from WVD virtual network for AADDS and DevOps
- [Windows Virtual Desktop Host Pool](https://docs.microsoft.com/en-us/azure/virtual-desktop/create-host-pools-azure-marketplace) and the host pool registration token will be exported as an output in the Terraform configuration
- [Windows Virtual Desktop Application Group](https://docs.microsoft.com/en-us/azure/virtual-desktop/manage-app-groups)
- Windows Virtual Desktop Workspace
- [Windows Virtual Machine(s)](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/quick-create-portal) with a [Custom Script Extension](https://docs.microsoft.com/en-us/azure/virtual-machines/extensions/custom-script-windows) to configure [WinRM for Ansible](https://docs.ansible.com/ansible/latest/user_guide/windows_winrm.html)
- A local Ansible inventory file which will include host name and IP to run the Ansible playbook against

## Terraform Setup

Terraform requires you to manage state files. You can choose to store remote state in [Azure Storage Account](https://docs.microsoft.com/en-us/azure/developer/terraform/store-state-in-azure-storage) or in [Terraform Cloud](https://www.terraform.io/cloud). Whichever solution you choose, be sure to update the [`backend.tf`](backend.tf) file to reflect your remote state solution. This repo uses Terraform Cloud and for the GitHub Action to work with your Terraform Cloud account, you will need to create an [API token](https://www.terraform.io/docs/cloud/users-teams-organizations/users.html#api-tokens) and save it as a [GitHub Secret](https://docs.github.com/en/actions/reference/encrypted-secrets#creating-encrypted-secrets-for-a-repository) named `TF_API_TOKEN`.

I chose to use Terraform Cloud storing remote state files. You also have the option of running your Terraform script on Terraform Cloud infrastructure, but I chose to run it locally on the GitHub self-hosted runner installed on my DevOps VM in Azure. This will enable the GitHub Action to use the Ansible inventory file when it comes time to call the Ansible playbook and reach WVD Session Host VMs by private IP as the self-hosted runner is deployed in a peered virtual network. Taking this route will require the use of an [Azure Service Principal](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/service_principal_client_secret) to run the Terraform commands. Once you have the secret values, enter them in GitHub Secrets using the following names 

- `ARM_CLIENT_ID`
- `ARM_CLIENT_SECRET`
- `ARM_SUBSCRIPTION_ID`
- `ARM_TENANT_ID`

> NOTE: You could name the GitHub secrets anything you want but you'll need to make sure they are consistent with what is in the [`terraform.yml`](./github/workflows/terraform.yml) workflow file.

This repo also includes variables for re-usability. The variable definitions can be found in the [`variables.tf`](variables.tf) file. The vaules for each deployment are maintained in a `*.tfvars` file and I've included a [`sample.tfvars`](sample.tfvars) file so you will need to update based on what is deployed in your environment.

To run the Terrafrom script locally, take a look at the [`terraform.yml`](./github/workflows/terraform.yml) workflow file. There you'll find a `terraform plan` and `terraform apply` command with all the arguments you'll need.

> NOTE: If you decide to change the name of the sample.tfvars file, you'll also need to update the filename in the workflow.

## Ansible Setup

The `site.yml` [Ansible Playbook](https://docs.ansible.com/ansible/latest/user_guide/playbooks.html) found in this repo relies on a few variables needed to connect to your VM, install the RDSAgent software for registering it as a WVD Session Host, and performing a domain join. Rather then saving credentials to the repo (which is never a good thing), we'll use `ansible-vault` to encrypt contents leveraging [Ansible Vault](https://docs.ansible.com/ansible/latest/user_guide/vault.html). The encrypted vault will be commited to the repo as `secrets.yml`. 

> NOTE: `secrets.yml` file in this repo contains info specific to my deployment so you'll need to overwrite it with your own.

Let's start by creating a vault file:

```sh
ansible-vault create secrets.yml
```

You will be prompted for a password. Enter a super-secret password. Make it hard to brute force ;-)

> NOTE: You will also need to save the vault password as a GitHub repo Secret named `ANSIBLE_VAULT_PASSWORD` for the GitHub Action workflow to use.

After the vault password has been set, a VI editor will open. 

> NOTE: Be sure to hit the `i` key to put yourself in `insert` mode and enter the following:

```text
ansible_user: <YOUR_VM_USERNAME>
ansible_password: <YOUR_VM_PASSWORD>
dns_domain_name: <YOUR_DOMAIN_NAME>
domain_admin_user: <YOUR_DOMAIN_USERNAME>
domain_admin_password: <YOUR_DOMAIN_PASSWORD>
domain_ou_path: <YOUR_DOMAIN_DISTINGUISHED_OU_PATH>
```

> NOTE: Save the file using the following command `:wq!`

If you need to update the vault, you can run the following command to edit the file:

```sh
ansible-vault edit secrets.yml
```

> NOTE: You will be prompted to enter your vault password

With the vault file saved to the repo, the GitHub Action workflow will use the `ANSIBLE_VAULT_PASSWORD` to unlock the vault when the Ansible playbook is invoked.

To view the Ansible playbook command, take a look at the [`terraform.yml`](./github/workflows/terraform.yml) workflow file and look for the Ansible Playbook task. You'll see that the command passes extra variables for the Host Pool registratin token and passes the variables found in `secrets.yml` vault file into the playbook. 

More on Ansible Secrets here:

- [Encrypting content with Ansible Vault](https://docs.ansible.com/ansible/latest/user_guide/vault.html)
- [Handling secrets in your Ansible playbooks](https://www.redhat.com/sysadmin/ansible-playbooks-secrets)

### GitHub Action Setup

If you configured all the secrets (listed in steps above), you will see a GitHub Action workflow running each time you do a push or pull request into the main branch. At this point, there's nothing else you need to do here. Now, go watch it run and have fun!!

## Clean Up

When you are ready to clean things up, you can run the following command:

```sh
terraform destroy -var-file=sample.tfvars -var=username=user -var=password=pass
```
