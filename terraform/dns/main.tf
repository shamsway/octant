# Cloudflare DNS records for Octant homelab
#
# Usage:
#   terraform apply -var="cloudflare_token=${CLOUDFLARE_TOKEN}"
#   terraform destroy -var="cloudflare_token=${CLOUDFLARE_TOKEN}"
#
# This module creates DNS records pointing to your home network devices.
# Update the device_records variable with your own hostnames and IPs.

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

variable "cloudflare_token" {
  description = "Cloudflare authentication TOKEN"
  type        = string
}

provider "cloudflare" {
  api_token = var.cloudflare_token
}

variable "domain_name" {
  description = "Domain managed in Cloudflare"
  default     = "example.com"
}

variable "device_records" {
  description = "Map of device names to IP addresses for DNS A records"
  type        = map(string)
  default = {
    # Add your devices here, e.g.:
    # "server-01" = "192.168.1.10"
    # "server-02" = "192.168.1.11"
  }
}

variable "cluster_nodes" {
  description = "List of cluster node IPs for consul/nomad/wildcard round-robin DNS"
  type        = list(string)
  default     = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}

data "cloudflare_zones" "domain" {
  filter {
    name = var.domain_name
  }
}

# Device A records
resource "cloudflare_record" "devices" {
  for_each        = var.device_records
  zone_id         = data.cloudflare_zones.domain.zones[0].id
  name            = each.key
  content         = each.value
  type            = "A"
  proxied         = false
  allow_overwrite = true
}

# Consul round-robin A records
resource "cloudflare_record" "consul" {
  count           = length(var.cluster_nodes)
  zone_id         = data.cloudflare_zones.domain.zones[0].id
  name            = "consul"
  content         = var.cluster_nodes[count.index]
  type            = "A"
  proxied         = false
  allow_overwrite = false
}

# Nomad round-robin A records
resource "cloudflare_record" "nomad" {
  count           = length(var.cluster_nodes)
  zone_id         = data.cloudflare_zones.domain.zones[0].id
  name            = "nomad"
  content         = var.cluster_nodes[count.index]
  type            = "A"
  proxied         = false
  allow_overwrite = true
}

# Wildcard round-robin A records
resource "cloudflare_record" "wildcard" {
  count           = length(var.cluster_nodes)
  zone_id         = data.cloudflare_zones.domain.zones[0].id
  name            = "*"
  content         = var.cluster_nodes[count.index]
  type            = "A"
  proxied         = false
  allow_overwrite = true
}
