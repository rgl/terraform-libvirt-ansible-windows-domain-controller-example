# see https://github.com/hashicorp/terraform
terraform {
  required_version = "1.13.4"
  required_providers {
    # see https://registry.terraform.io/providers/hashicorp/random
    # see https://github.com/hashicorp/terraform-provider-random
    random = {
      source  = "hashicorp/random"
      version = "3.7.2"
    }
    # see https://registry.terraform.io/providers/hashicorp/cloudinit
    # see https://github.com/hashicorp/terraform-provider-cloudinit
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.7"
    }
    # see https://registry.terraform.io/providers/dmacvicar/libvirt
    # see https://github.com/dmacvicar/terraform-provider-libvirt
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.8.3"
    }
    # see https://registry.terraform.io/providers/ansible/ansible
    # see https://github.com/ansible/terraform-provider-ansible
    ansible = {
      source  = "ansible/ansible"
      version = "1.3.0"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

variable "prefix" {
  type    = string
  default = "terraform-libvirt-ansible-windows-domain-controller-example"
}

variable "workspace_path" {
  type = string
}

variable "winrm_username" {
  type    = string
  default = "vagrant"
}

variable "winrm_password" {
  type      = string
  sensitive = true
  # set the administrator password.
  # NB the administrator password will be reset to this value by the cloudbase-init SetUserPasswordPlugin plugin.
  # NB this value must meet the Windows password policy requirements.
  #    see https://docs.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/password-must-meet-complexity-requirements
  default = "HeyH0Password"
}

# NB this uses the vagrant windows image imported from https://github.com/rgl/windows-vagrant.
variable "base_volume_name" {
  type    = string
  default = "windows-2022-uefi-amd64_vagrant_box_image_0.0.0_box_0.img"
}

output "dc_ip_address" {
  value = local.dc_ip_address
}

output "dm_ip_address" {
  value = local.dm_ip_address
}

locals {
  example_ip_cidr = "10.17.3.0/24"
  dc_ip_address   = "10.17.3.2"
  dm_ip_address   = "10.17.3.10"
}

# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.8.3/website/docs/r/network.markdown
resource "libvirt_network" "example" {
  name      = var.prefix
  mode      = "nat"
  domain    = "example.test"
  addresses = [local.example_ip_cidr]
  dhcp {
    enabled = true
  }
  dns {
    enabled    = true
    local_only = false
  }
}
