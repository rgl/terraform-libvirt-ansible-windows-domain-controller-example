# see https://github.com/hashicorp/terraform
terraform {
  required_version = "1.16.3"
  required_providers {
    # see https://registry.terraform.io/providers/hashicorp/random
    # see https://github.com/hashicorp/terraform-provider-random
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
    # see https://registry.terraform.io/providers/northwood-labs/corefunc
    # see https://github.com/northwood-labs/terraform-provider-corefunc
    corefunc = {
      source  = "northwood-labs/corefunc"
      version = "2.3.0"
    }
    # see https://registry.terraform.io/providers/hashicorp/cloudinit
    # see https://github.com/hashicorp/terraform-provider-cloudinit
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.4.1"
    }
    # see https://registry.terraform.io/providers/dmacvicar/libvirt
    # see https://github.com/dmacvicar/terraform-provider-libvirt
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.9.9"
    }
    # see https://registry.terraform.io/providers/ansible/ansible
    # see https://github.com/ansible/terraform-provider-ansible
    ansible = {
      source  = "ansible/ansible"
      version = "1.5.0"
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
variable "dc_base_volume_name" {
  type    = string
  default = "windows-2025-uefi-amd64_vagrant_box_image_0.0.0_box_0.img"
}

# NB this uses the vagrant windows image imported from https://github.com/rgl/windows-vagrant.
variable "dm_base_volume_name" {
  type    = string
  default = "windows-11-24h2-uefi-amd64_vagrant_box_image_0.0.0_box_0.img"
}

output "dc1_ip_address" {
  value = local.dcs[0].ip_address
}

output "dc2_ip_address" {
  value = local.dcs[1].ip_address
}

output "dm_ip_address" {
  value = local.dm_ip_address
}

# see https://en.wikipedia.org/wiki/MAC_address#Ranges_of_group_and_locally_administered_addresses
locals {
  example_ip_cidr = "10.17.3.0/24"
  dcs = [
    for i in range(2, 2 + 2) : {
      mac_address = format("02:00:00:00:00:%02x", i)
      ip_address  = "10.17.3.${i}"
    }
  ]
  dm_mac_address = format("02:00:00:00:00:%02x", 10)
  dm_ip_address  = "10.17.3.10"
}

locals {
  cpu_sockets = 1
  cpu_cores   = 4
  cpu_threads = 1
  memory_mb   = 4 * 1024
}

# see https://gitlab.com/libosinfo/osinfo-db/-/blob/main/data/os/microsoft.com/win-2k22.xml.in
# see https://gitlab.com/libosinfo/osinfo-db/-/blob/main/data/os/microsoft.com/win-2k25.xml.in
# see https://gitlab.com/libosinfo/osinfo-db/-/blob/main/data/os/microsoft.com/win-11.xml.in
locals {
  windows_version_to_os_map = {
    "2022" = "2k22"
    "2025" = "2k25"
    "11"   = "11"
  }
  dc_os_id = "http://microsoft.com/win/${lookup(local.windows_version_to_os_map, regex("windows-([^-]+)", var.dc_base_volume_name)[0], "2k22")}"
  dm_os_id = "http://microsoft.com/win/${lookup(local.windows_version_to_os_map, regex("windows-([^-]+)", var.dm_base_volume_name)[0], "2k22")}"
}

# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.9/docs/resources/network
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/docs/resources/network.md
resource "libvirt_network" "example" {
  name = var.prefix
  forward = {
    nat = {
      ports = [
        {
          start = 1024
          end   = 65535
        }
      ]
    }
  }
  domain = {
    name = "example.test"
  }
  ips = [
    {
      address = cidrhost(local.example_ip_cidr, 1)
      netmask = cidrnetmask(local.example_ip_cidr)
      dhcp = {
        ranges = [
          {
            start = cidrhost(local.example_ip_cidr, 2)
            end   = cidrhost(local.example_ip_cidr, -2)
          }
        ]
        hosts = concat(
          [
            for dc in local.dcs : {
              mac = dc.mac_address
              ip  = dc.ip_address
            }
          ],
          [
            {
              mac = local.dm_mac_address
              ip  = local.dm_ip_address
            }
          ]
        )
      }
    }
  ]
}
