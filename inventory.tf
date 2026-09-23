resource "ansible_group" "all" {
  name     = "all"
  children = [ansible_group.dcs.name, ansible_group.dms.name]
  variables = {
    # connection configuration.
    # see https://docs.ansible.com/ansible-core/2.20/collections/ansible/builtin/psrp_connection.html
    ansible_user                    = var.winrm_username
    ansible_password                = var.winrm_password
    ansible_connection              = "psrp"
    ansible_psrp_protocol           = "http"
    ansible_psrp_message_encryption = "never"
    ansible_psrp_auth               = "credssp"

    # common variables.
    windows_dns_domain_name               = "example.test"
    windows_domain_controller1_ip_address = local.dcs[0].ip_address
    windows_domain_controller2_ip_address = local.dcs[1].ip_address
  }
}

resource "ansible_group" "dcs" {
  name = "dcs"
  variables = {
  }
}

resource "ansible_group" "dms" {
  name = "dms"
  variables = {
  }
}

resource "ansible_host" "dc" {
  count  = length(local.dcs)
  name   = "dc${count.index + 1}"
  groups = [ansible_group.dcs.name]
  variables = {
    ansible_host = one(flatten([
      for interface in data.libvirt_domain_interface_addresses.dc[count.index].interfaces : [
        for addr in interface.addrs : addr.addr
        if addr.type == "ipv4" && provider::corefunc::net_cidr_contains(local.example_ip_cidr, addr.addr)
      ]
    ]))
  }
}

resource "ansible_host" "dm" {
  name   = "dm"
  groups = [ansible_group.dms.name]
  variables = {
    ansible_host = one(flatten([
      for interface in data.libvirt_domain_interface_addresses.dm.interfaces : [
        for addr in interface.addrs : addr.addr
        if addr.type == "ipv4" && provider::corefunc::net_cidr_contains(local.example_ip_cidr, addr.addr)
      ]
    ]))
  }
}
