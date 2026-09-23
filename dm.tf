# NB this generates a single random number for the cloud-init instance-id.
resource "random_id" "dm" {
  byte_length = 10
}

# a multipart cloudbase-init cloud-config.
# NB the parts are executed by their declared order.
# see https://github.com/cloudbase/cloudbase-init
# see https://cloudbase-init.readthedocs.io/en/1.1.8/userdata.html#cloud-config
# see https://cloudbase-init.readthedocs.io/en/1.1.8/userdata.html#userdata
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
# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.9/docs/resources/cloudinit_disk
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/docs/resources/cloudinit_disk.md
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/internal/provider/cloudinit_disk_resource.go#L291-L341
resource "libvirt_cloudinit_disk" "dm_cloudinit" {
  name = "${var.prefix}_dm_cloudinit.iso"
  meta_data = jsonencode({
    "instance-id" : random_id.dm.hex,
    "local-hostname" : "dm",
  })
  user_data = data.cloudinit_config.dm.rendered
}

# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.9/docs/resources/volume
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/docs/resources/volume.md
resource "libvirt_volume" "dm_cloudinit" {
  pool = "default"
  name = "${var.prefix}_dm_cloudinit.iso"
  create = {
    content = {
      url = libvirt_cloudinit_disk.dm_cloudinit.path
    }
  }
}

# this uses the vagrant windows image imported from https://github.com/rgl/windows-vagrant.
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/website/docs/r/volume.html.markdown
resource "libvirt_volume" "dm_root" {
  pool     = "default"
  name     = "${var.prefix}_dm_root.img"
  capacity = 66 * 1024 * 1024 * 1024 # 66GiB. this root FS is automatically resized by cloudbase-init (by its cloudbaseinit.plugins.windows.extendvolumes.ExtendVolumesPlugin plugin which is included in the rgl/windows-vagrant image).
  target = {
    format = {
      type = "qcow2"
    }
  }
  backing_store = {
    format = {
      type = "qcow2"
    }
    path = "/var/lib/libvirt/images/${var.dm_base_volume_name}"
  }
}

# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.9/docs/resources/domain
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/docs/resources/domain.md
resource "libvirt_domain" "dm" {
  name        = "${var.prefix}-dm"
  description = "see ${var.workspace_path}"
  running     = true
  type        = "kvm"
  vcpu        = local.cpu_sockets * local.cpu_cores * local.cpu_threads
  memory      = local.memory_mb
  memory_unit = "MiB"
  features = {
    acpi = true
    apic = {}
    hyper_v = {
      mode = "passthrough"
    }
    vm_port = {
      state = "off"
    }
  }
  metadata = {
    xml = <<-EOF
      <libosinfo:libosinfo xmlns:libosinfo="http://libosinfo.org/xmlns/libvirt/domain/1.0">
        <libosinfo:os id="${local.dm_os_id}"/>
      </libosinfo:libosinfo>
      EOF
  }
  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    firmware     = "efi"
  }
  cpu = {
    mode = "host-passthrough"
    topology = {
      sockets = local.cpu_sockets
      cores   = local.cpu_cores
      threads = local.cpu_threads
    }
  }
  clock = {
    offset = "localtime"
    timer = [
      {
        name        = "rtc"
        tick_policy = "catchup"
      },
      {
        name        = "pit"
        tick_policy = "delay"
      },
      {
        name    = "hpet"
        present = "no"
      },
      {
        name    = "hypervclock"
        present = "yes"
      },
    ]
  }
  devices = {
    graphics = [
      {
        spice = {
          auto_port = true
          listeners = [
            {
              address = {}
            }
          ]
        }
      }
    ]
    videos = [
      {
        model = {
          type    = "qxl"
          primary = "yes"
          vram    = 65536
          ram     = 65536
          vga_mem = 16384
          heads   = 1
        }
      }
    ]
    controllers = [
      {
        type  = "scsi"
        model = "virtio-scsi"
      },
      {
        type = "virtio-serial"
      }
    ]
    channels = [
      {
        source = {
          unix = {
            mode = "bind"
          }
        }
        target = {
          virt_io = {
            name = "org.qemu.guest_agent.0"
          }
        }
      },
      {
        source = {
          spice_vmc = true
        }
        target = {
          virt_io = {
            name = "com.redhat.spice.0"
          }
        }
      }
    ]
    rngs = [
      {
        model = "virtio"
        backend = {
          random = "/dev/urandom"
        }
      }
    ]
    disks = [
      {
        driver = {
          name = "qemu"
          type = "qcow2"
        }
        source = {
          volume = {
            pool   = libvirt_volume.dm_root.pool
            volume = libvirt_volume.dm_root.name
          }
        }
        block_io = {
          # set the discard_granularity to make windows happy.
          # NB when using a qemu/kvm based hypervisor, ssd trim is only available when
          #    discard_granularity is set to 8K (or higher), otherwise,
          #    defrag.exe C: /H /L fails as: Incorrect function. (0x80070001) error.
          #    NB when using proxmox, there is no explicit way to set discard_granularity.
          #       it could be set using qemu_additional_args argument, but when using
          #       non-root user token, that fails as: only root can set 'args' config, so
          #       we do not do it.
          #    see lsblk -o NAME,PHY-SEC,LOG-SEC,DISC-GRAN,DISC-ALN
          #    see fsutil.exe behavior query DisableDeleteNotify
          #    see /etc/libvirt/qemu/{vm_name}.xml (when using libvirt).
          #    see /etc/pve/qemu-server/{vm_id}.conf (when using proxmox).
          # see https://libvirt.org/formatdomain.html
          # see https://github.com/virtio-win/kvm-guest-drivers-windows/issues/1574
          discard_granularity = 8 * 1024
        }
        target = {
          bus = "scsi"
          dev = "sda"
        }
        wwn = format("000000000000aa%02x", 0)
      },
      {
        device = "cdrom"
        source = {
          volume = {
            pool   = libvirt_volume.dm_cloudinit.pool
            volume = libvirt_volume.dm_cloudinit.name
          }
        }
        target = {
          bus = "scsi"
          dev = "hdd"
        }
        serial = "cloudinit"
      }
    ]
    interfaces = [
      {
        type = "network"
        model = {
          type = "virtio"
        }
        mac = {
          address = local.dm_mac_address
        }
        source = {
          network = {
            network = libvirt_network.example.name
          }
        }
        wait_for_ip = {
          network = local.example_ip_cidr
          source  = "agent"
          timeout = 300 # 300s (5m).
        }
      }
    ]
  }
}

# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.9/docs/data-sources/domain_interface_addresses
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/docs/data-sources/domain_interface_addresses.md
data "libvirt_domain_interface_addresses" "dm" {
  domain = libvirt_domain.dm.name
  source = "agent"
}
