# terraform apply -var="TAILSCALE_KEY=${TAILSCALE_CLOUD_KEY}" -var="cloudflare_token=${CLOUDFLARE_TOKEN}"
# terraform destroy -var="TAILSCALE_KEY=${TAILSCALE_CLOUD_KEY}" -var="cloudflare_token=${CLOUDFLARE_TOKEN}"

terraform {
  required_providers {
    google = { }
    tailscale = {
      source = "tailscale/tailscale"
      version = "0.15.0"
    }    
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "google" {
    project = "shamsway"
    region  = "us-central1"

}

# variable "TAILSCALE_KEY" {
#   description = "Tailscale authentication key"
#   type        = string
# }

variable "cloudflare_token" {
  description = "Cloudflare authentication token"
  type        = string
}

provider "cloudflare" {
  api_token = "${var.cloudflare_token}"
}

variable "domain_name" {
  default = "shamsway.net"
}

data "cloudflare_zones" "domain" {
  filter {
    name = var.domain_name
  }
}

resource "tailscale_tailnet_key" "key" {
  description   = "Ephemeral key for phil"
  reusable      = true
  ephemeral     = false
  preauthorized = true
  tags          = ["tag:cloud"]
}

data "google_compute_zones" "available" {
  region = "us-central1"
}

resource "google_compute_network" "vpc_network" {
  name                    = "shamsway-vpc-usc1"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "vpc_subnetwork" {
  name          = "sparklepants"
  ip_cidr_range = "192.168.250.0/24"
  region        = "us-central1"
  network       = google_compute_network.vpc_network.self_link

  stack_type       = "IPV4_IPV6"
  ipv6_access_type = "EXTERNAL"
}

# Disable default SSH rule - Terraform can't do this, so use gcloud cli or API
# resource "google_compute_firewall" "disable_default_ssh" {
#   name    = "default-allow-ssh"
#   network = google_compute_network.vpc_network.self_link

#   allow {
#     protocol = "tcp"
#     ports    = ["22"]
#   }

#   source_ranges = ["0.0.0.0/0"]
#   target_tags   = ["default-allow-ssh"]

#   disabled = true
# }

# Add IAP, Home IP
resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = google_compute_network.vpc_network.self_link

  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20", "162.211.39.153/32"]
  target_tags   = ["allow-ssh"]
}

# Create rules for Tailscale
resource "google_compute_firewall" "allow_tailscale_udp_ipv4" {
  name    = "allow-tailscale-udp-ipv4"
  network = google_compute_network.vpc_network.self_link

  allow {
    protocol = "udp"
    ports    = ["41641"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "allow_tailscale_udp_ipv6" {
  name    = "allow-tailscale-udp-ipv6"
  network = google_compute_network.vpc_network.self_link

  allow {
    protocol = "udp"
    ports    = ["41641"]
  }

  source_ranges = ["::/0"]
}


resource "google_compute_instance" "phil" {
  name         = "phil"
  machine_type = "f1-micro"
  zone         = data.google_compute_zones.available.names[0]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 30
    }
  }

  tags = ["allow-ssh"]

  scheduling {
    preemptible       = true
    automatic_restart = false
    provisioning_model          = "SPOT"
    instance_termination_action = "STOP"  
  }

  metadata = {
    ssh-keys = "matt:${file("~/.ssh/id_rsa.pub")}\nmatt:${file("~/.ssh/id_rsa.pub")}"
    shutdown-script = "#! /bin/bash sudo tailscale logout"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /root/.ssh",
      "sudo cp /home/matt/.ssh/authorized_keys /root/.ssh/",
      "sudo sed -i -e 's/#PermitRootLogin no/PermitRootLogin without-password/' -e 's/PermitRootLogin no/PermitRootLogin without-password/' /etc/ssh/sshd_config",
      "sudo systemctl restart sshd"
    ]
  }

  provisioner "remote-exec" {
    when = destroy
    inline = [ "sudo tailscale logout" ]
  }

  network_interface {
    subnetwork = google_compute_subnetwork.vpc_subnetwork.self_link
    stack_type = "IPV4_IPV6"
    access_config {
      network_tier = "STANDARD"
    }
  }

  connection {
    type        = "ssh"
    user        = "matt"
    private_key = file("~/.ssh/id_rsa")
    host        = self.network_interface[0].access_config[0].nat_ip
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    useradd -md /user/matt matt
    curl -fsSL https://tailscale.com/install.sh | sh
    tailscale up --accept-routes --authkey=${tailscale_tailnet_key.key.key}
  EOT
}

data "tailscale_device" "phil" {
  depends_on = [google_compute_instance.phil]
  hostname = google_compute_instance.phil.name
  wait_for = "30s"
  }

resource "cloudflare_record" "phil" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "phil"
  value   = data.tailscale_device.phil.addresses[0]
  type    = "A"
  proxied = false
  allow_overwrite = true

  # lifecycle {
  #   ignore_changes = all
  #   prevent_destroy = true
  # }
}

resource "null_resource" "manage_known_hosts" {
  triggers = {
    hostname = "${cloudflare_record.phil.name}.${var.domain_name}"
  }

  provisioner "local-exec" {
    command = "ssh-keyscan -H ${self.triggers.hostname} >> ~/.ssh/known_hosts"
    on_failure = continue
  }

  provisioner "local-exec" {
    when = destroy
    command = "ssh-keygen -R ${self.triggers.hostname}"
  }
}

output "tailscale_ip" {
  value = data.tailscale_device.phil.addresses[0]
}

output "tailscale_id" {
  value = data.tailscale_device.phil.id
}