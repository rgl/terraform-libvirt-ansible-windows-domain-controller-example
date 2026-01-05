# NB this generates a single random number for the cloud-init instance-id.
resource "random_id" "dm" {
  byte_length = 10
}

# a multipart cloudbase-init cloud-config.
# NB the parts are executed by their declared order.
# see https://github.com/cloudbase/cloudbase-init
# see https://cloudbase-init.readthedocs.io/en/1.1.6/userdata.html#cloud-config
# see https://cloudbase-init.readthedocs.io/en/1.1.6/userdata.html#userdata
# see https://registry.terraform.io/providers/hashicorp/cloudinit/latest/docs/data-sources/config
# see https://www.terraform.io/docs/configuration/expressions.html#string-literals
data "cloudinit_config" "dm" {
  gzip          = false
  base64_encode = false
  part {
    content_type = "text/cloud-config"
    content      = <<-EOF
      #cloud-config
      timezone: Europe/Lisbon
      users:
        - name: ${jsonencode(var.winrm_username)}
          passwd: ${jsonencode(var.winrm_password)}
          primary_group: Administrators
          ssh_authorized_keys:
            - ${jsonencode(trimspace(file("~/.ssh/id_rsa.pub")))}
      EOF
  }
}

# a cloudbase-init cloud-config disk.
# NB this creates an iso image that will be used by the NoCloud cloudbase-init datasource.
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.8.3/website/docs/r/cloudinit.html.markdown
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.8.3/libvirt/cloudinit_def.go#L139-L168
resource "libvirt_cloudinit_disk" "dm_cloudinit" {
  name = "${var.prefix}_dm_cloudinit.iso"
  meta_data = jsonencode({
    "instance-id" : random_id.dm.hex,
    "local-hostname" : "dm",
  })
  user_data = data.cloudinit_config.dm.rendered
}

# this uses the vagrant windows image imported from https://github.com/rgl/windows-vagrant.
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.8.3/website/docs/r/volume.html.markdown
resource "libvirt_volume" "dm_root" {
  name             = "${var.prefix}_dm_root.img"
  base_volume_name = var.base_volume_name
  format           = "qcow2"
}

# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.8.3/website/docs/r/domain.html.markdown
resource "libvirt_domain" "dm" {
  name        = "${var.prefix}-dm"
  description = "see ${var.workspace_path}"
  machine     = "q35"
  firmware    = "/usr/share/OVMF/OVMF_CODE_4M.fd"
  cpu {
    mode = "host-passthrough"
  }
  vcpu   = 4
  memory = 4 * 1024
  video {
    type = "qxl"
  }
  xml {
    xslt = file("libvirt-domain.xsl")
  }
  qemu_agent = true
  cloudinit  = libvirt_cloudinit_disk.dm_cloudinit.id
  disk {
    volume_id = libvirt_volume.dm_root.id
    scsi      = true
  }
  network_interface {
    network_id     = libvirt_network.example.id
    wait_for_lease = true
    hostname       = "dm"
    addresses      = [local.dm_ip_address]
  }
}
