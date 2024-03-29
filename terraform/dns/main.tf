# terraform apply -var="cloudflare_token=${CLOUDFLARE_TOKEN}"
# terraform destroy -var="cloudflare_token=${CLOUDFLARE_TOKEN}"

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    tailscale = {
    source = "tailscale/tailscale"
    version = "0.15.0"
    }    
  }
}

data "tailscale_device" "phil" {
  hostname = "phil"
  wait_for = "30s"
  }

variable "cloudflare_token" {
  description = "Cloudflare authentication TOKEN"
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

resource "cloudflare_record" "jerry" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "jerry"
  value   = "192.168.252.6"
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "bobby" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "bobby"
  value   = "192.168.252.7"
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "billy" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "billy"
  value   = "192.168.252.8"
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "phil" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "phil"
  value   = data.tailscale_device.phil.addresses[0]
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "consul-a01" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "consul"
  value   = cloudflare_record.jerry.value
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "consul-a02" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "consul"
  value   = cloudflare_record.bobby.value
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "nomad-a01" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "nomad"
  value   = cloudflare_record.jerry.value
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "nomad-a02" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "nomad"
  value   = cloudflare_record.bobby.value
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "wildcardmad-a01" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "*"
  value   = cloudflare_record.jerry.value
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "wildcardmad-a02" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "*"
  value   = cloudflare_record.bobby.value
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "wildcardmad-a03" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "*"
  value   = cloudflare_record.billy.value
  type    = "A"
  proxied = false
  allow_overwrite = true
}