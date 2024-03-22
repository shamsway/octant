packer {
    required_plugins {
      vmware = {
        version = ">= 1.0.11"
        source  = "github.com/hashicorp/vmware"
      }
    }
  }

variable "ssh_username" {
  default = "root" 
}

variable "ssh_password" {
  default = "packer" 
}

variable "builderip" { 
  default = "192.168.252.5"
}

source "vmware-iso" "vmware" {
  vm_name              = "octantnode"
  output_directory     = "output-octantnode"
  format               = "ovf"
  guest_os_type        = "debian12-64"
  memory               = 20480
  disk_size            = 20480
  disk_additional_size = [40960]
  ovftool_options      = ["--noImageFiles"]
  #network              = "vmnet3"
  vmx_data = {
    "ethernet0.address"         = "00:50:56:BE:EE:EF" 
    "ethernet0.addressType"     = "static"
    "ethernet0.present"         = "TRUE",
    "ethernet0.startConnected"  = "TRUE", 
    "ethernet0.connectionType"  = "nat",
    "ethernet0.virtualDev"      = "vmxnet3"
  }
  iso_url              = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso"
  iso_checksum         = "sha256:013f5b44670d81280b5b1bc02455842b250df2f0c6763398feb69af1a805a14f"
  ssh_username         = var.ssh_username
  ssh_password         = var.ssh_password
  ssh_timeout          = "20m"
  shutdown_command     = "sudo shutdown -Ph now"
  #http_directory       = "http"
  http_content = { 
    "/preseed.cfg" = file("http/preseed.cfg")
  }   
  boot_command         = [
  "<esc><wait>auto url=http://${var.builderip}:{{ .HTTPPort }}/preseed.cfg<enter>"
  ]
}

build {
  sources = ["source.vmware-iso.vmware"]

/*   provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y cloud-init zfsutils-linux",
      "sudo zpool create -f zfspool /dev/sdb",
      "sudo zfs create -o mountpoint=/mnt/zfs zfspool/data",
      "sudo chown -R ${var.ssh_username}:${var.ssh_username} /mnt/zfs"
    ]
  } */

  provisioner "file" {
    destination = "/root/.bash_profile"
    source      = "files/bash_profile.sh"
  }

  provisioner "file" {
    destination = "/root/.bash_prompt"
    source      = "files/bash_prompt.sh"
  }

  provisioner "file" {
    destination = "/tmp/cloud-init.cfg"
    source      = "files/cloud-init.cfg"
  }

  provisioner "shell" {
    inline = [
      "mkdir -p /etc/cloud/cloud.cfg.d/ && cp /tmp/cloud-init.cfg /etc/cloud/cloud.cfg.d/99-octant.cfg"
    ]
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    scripts          = [
      "scripts/debian-octant-config.sh",
      "scripts/debian-ova-cleanup.sh"
    ]
  }

  post-processor "shell-local" {
    environment_vars = [
      "APPLIANCE_NAME=octantnode",
      "APPLIANCE_VERSION=1",
      "APPLIANCE_OVA=octantnode"
    ]

    use_linux_pathing = false

    # Run the PowerShell script on Windows
    inline = [
      "cd postprocess-ova-properties",
      "powershell -ExecutionPolicy bypass -file add_ovf_properties.ps1"
    ]
  }

  post-processor "manifest" {
    output = "manifest.json"
  }
}