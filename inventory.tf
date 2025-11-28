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
    windows_dns_domain_name              = "example.test"
    windows_domain_controller_ip_address = local.dc_ip_address
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
  name   = "dc"
  groups = [ansible_group.dcs.name]
  variables = {
    ansible_host = length(libvirt_domain.dc.network_interface[0].addresses) > 0 ? libvirt_domain.dc.network_interface[0].addresses[0] : ""
  }
}

resource "ansible_host" "dm" {
  name   = "dm"
  groups = [ansible_group.dms.name]
  variables = {
    ansible_host = length(libvirt_domain.dm.network_interface[0].addresses) > 0 ? libvirt_domain.dm.network_interface[0].addresses[0] : ""
  }
}
