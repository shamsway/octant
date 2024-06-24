# unset CLOUDFLARE_API_KEY

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
    project = "octant-426722"
    region  = "us-central1"

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

resource "google_compute_route" "home_lab_route" {
  name         = "home-lab-route"
  dest_range   = "192.168.252.0/24"
  network      = google_compute_network.vpc_network.self_link
  next_hop_instance = google_compute_instance.phil.self_link
  priority     = 1000
}

resource "google_dns_managed_zone" "consul" {
  name        = "private-zone"
  dns_name    = "service.consul."
  description = "Private DNS zone for service.consul"

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.vpc_network.self_link
    }
  }

  forwarding_config {
    target_name_servers {
      ipv4_address = "192.168.252.1"
    }
  }
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
  name           = "phil"
  machine_type   = "f1-micro"
  zone           = data.google_compute_zones.available.names[0]
  can_ip_forward = true

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
    ssh-keys = <<EOT
      root:${file("~/.ssh/id_rsa.pub")}
      matt:${file("~/.ssh/id_rsa.pub")}
    EOT
    shutdown-script = file("${path.module}/shutdown-script.sh")
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    useradd -G sudoers -md /user/matt matt
    mkdir -p /etc/systemd/resolved.conf.d/
    cat > /etc/systemd/resolved.conf.d/conditional_forwarding.conf <<-EOL
    [Resolve]
    DNS=192.168.252.1
    Domains=~service.consul
    EOL
    systemctl restart systemd-resolved
  EOT

  provisioner "remote-exec" {
    inline = [
      "sudo curl -fsSL https://tailscale.com/install.sh | sh",
      "sudo tailscale up --accept-routes --accept-dns=false --authkey=${tailscale_tailnet_key.key.key} --advertise-routes=${google_compute_subnetwork.vpc_subnetwork.ip_cidr_range},35.199.192.0/19 --stateful-filtering=false --snat-subnet-routes=false",
      "sudo tailscale status",
      "sudo sysctl -w net.ipv4.ip_forward=1",
      "sudo sysctl -p",
      "sudo echo \"net.ipv4.ip_forward=1\" >> /etc/sysctl.conf",
      "sudo iptables -t mangle -A FORWARD -i tailscale0 -o ens4 -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu",
      "sudo /usr/sbin/iptables-save > /etc/iptables/rules.v4",   
      "sudo apt install -y python3 python3-paho-mqtt",
      "sudo chmod 777 /usr/local/bin",
      "sudo mkdir -p /root/.ssh",
      "sudo cp /home/matt/.ssh/authorized_keys /root/.ssh/",
      "sudo sed -i -e 's/#PermitRootLogin no/PermitRootLogin without-password/' -e 's/PermitRootLogin no/PermitRootLogin without-password/' /etc/ssh/sshd_config",
      "sudo systemctl restart sshd"
    ]
  }

  # Copy the preempt Python script to the VM
  provisioner "file" {
    source      = "${path.module}/preempt-notify.py"
    destination = "/usr/local/bin/preempt-notify.py"
  }

  # Copy the shutdown  script to the VM
  provisioner "file" {
    source      = "${path.module}/shutdown-script.sh"
    destination = "/usr/local/bin/shutdown-script.sh"
  }  

  provisioner "remote-exec" {
    inline = [ "sudo chmod +x /usr/local/bin/shutdown-script.sh" ]
  }

  provisioner "remote-exec" {
    when = destroy
    on_failure = continue
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
    type         = "ssh"
    user          = "matt"
    private_key = file("~/.ssh/id_rsa")
    host        = self.network_interface[0].access_config[0].nat_ip
  }

  lifecycle {
    ignore_changes = [ network_interface ]
  }
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