
terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
      version = "0.7.6"
    }
  }
}

terraform {
  required_version = ">= 1.6.6"
}

provider "libvirt" {
  # Configuration du fournisseur libvirt
  uri = "qemu:///system"
}

// variables that can be overridden
variable "hostname" { default = "test" }
variable "domain" { default = "example.com" }
variable "dhcp" { default = "dhcp" } # dhcp is other valid type
variable "memoryMB" { default = 1024*1 }
variable "cpu" { default = 1 }

// Create unique disk volumes for each VM
resource "libvirt_volume" "os_image" {
  count = 4
  name = "${var.hostname}-${count.index + 1}-os_image"
  pool = "default"
  source = "jammy-server-cloudimg-amd64-backup.img"
  format = "qcow2"
}

// Use CloudInit ISO to add ssh-key to the instance
resource "libvirt_cloudinit_disk" "commoninit" {
  name = "${var.hostname}-commoninit.iso"
  pool = "default"
  user_data      = data.template_cloudinit_config.config.rendered
  network_config = data.template_file.network_config.rendered
}

data "template_file" "user_data" {
  template = file("${path.module}/cloud_init.cfg")
  vars = {
    hostname = var.hostname
    fqdn = "${var.hostname}.${var.domain}"
    public_key = file("~/.ssh/id_ed25519.pub")
  }
}

data "template_cloudinit_config" "config" {
  gzip = false
  base64_encode = false
  part {
    filename = "init.cfg"
    content_type = "text/cloud-config"
    content = "${data.template_file.user_data.rendered}"
  }
}

data "template_file" "network_config" {
  template = file("${path.module}/network_config_${var.dhcp}.cfg")
}

// Create multiple machines with unique disks
resource "libvirt_domain" "domain-ubuntu" {
  count = 4

  # unique domain name in libvirt, not hostname
  name = "${var.hostname}-${count.index + 1}"
  memory = var.memoryMB
  vcpu = var.cpu

  disk {
    volume_id = libvirt_volume.os_image[count.index].id
  }
  network_interface {
    network_name = "default"
    wait_for_lease = true
  }

  cloudinit = libvirt_cloudinit_disk.commoninit.id
  qemu_agent = true
  
  # IMPORTANT
  # Ubuntu can hang if an isa-serial is not present at boot time.
  # If you find your CPU 100% and never is available, this is why
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type = "spice"
    listen_type = "address"
    autoport = "true"
  }
}

output "ips" {
  value = libvirt_domain.domain-ubuntu[*].network_interface.0.addresses
}
