# DNS records for lab.shamsway.net (Octant VM cluster)
#
# Usage:
#   terraform apply -var="cloudflare_token=${CLOUDFLARE_TOKEN}"
#   terraform destroy -var="cloudflare_token=${CLOUDFLARE_TOKEN}"

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

variable "cloudflare_token" {
  description = "Cloudflare API token"
  type        = string
}

variable "domain_name" {
  description = "Parent domain managed in Cloudflare"
  default     = "shamsway.net"
}

variable "lab_subdomain" {
  description = "Lab subdomain prefix"
  default     = "lab"
}

variable "hypervisor_ip" {
  description = "Hypervisor internal IP address"
  default     = "10.216.113.177"
}

variable "consul_ips" {
  description = "Consul server IPs (all VM nodes)"
  type        = list(string)
  default     = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}

provider "cloudflare" {
  api_token = var.cloudflare_token
}

data "cloudflare_zones" "domain" {
  filter {
    name = var.domain_name
  }
}

# Wildcard record: *.lab.shamsway.net -> hypervisor
# All service traffic routes through HAProxy on the hypervisor
resource "cloudflare_record" "lab_wildcard" {
  zone_id         = data.cloudflare_zones.domain.zones[0].id
  name            = "*.${var.lab_subdomain}"
  content         = var.hypervisor_ip
  type            = "A"
  proxied         = false
  allow_overwrite = true
}

# Base record: lab.shamsway.net -> hypervisor
# For direct access to the lab subdomain itself
resource "cloudflare_record" "lab_base" {
  zone_id         = data.cloudflare_zones.domain.zones[0].id
  name            = var.lab_subdomain
  content         = var.hypervisor_ip
  type            = "A"
  proxied         = false
  allow_overwrite = true
}

# Consul A records: consul.lab.shamsway.net -> all VM nodes
# Round-robin DNS for Consul API access from inside containers
resource "cloudflare_record" "consul" {
  count           = length(var.consul_ips)
  zone_id         = data.cloudflare_zones.domain.zones[0].id
  name            = "consul.${var.lab_subdomain}"
  content         = var.consul_ips[count.index]
  type            = "A"
  proxied         = false
  allow_overwrite = true
}
