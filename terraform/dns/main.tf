# unset CLOUDFLARE_API_KEY
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
  default = "octant.net"
}

data "cloudflare_zones" "domain" {
  filter {
    name = var.domain_name
  }
}

resource "cloudflare_record" "edgerouter" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "edgerouter"
  content = "192.168.1.1"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "joan" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "joan"
  content = "192.168.1.5"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "jerry" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "jerry"
  content = "192.168.1.6"
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "bobby" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "bobby"
  content = "192.168.1.7"
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "billy" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "billy"
  content = "192.168.1.8"
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "robert" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "robert"
  content = "192.168.1.10"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "phil" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "phil"
  content = data.tailscale_device.phil.addresses[0]
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "consul-a01" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "consul"
  content = cloudflare_record.jerry.content
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "consul-a02" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "consul"
  content = cloudflare_record.bobby.content
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "consul-a03" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "consul"
  content = cloudflare_record.billy.content
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "consul-a04" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "consul"
  content = cloudflare_record.robert.content
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "nomad-a01" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "nomad"
  content = cloudflare_record.jerry.content
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "nomad-a02" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "nomad"
  content = cloudflare_record.bobby.content
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "nomad-a03" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "nomad"
  content = cloudflare_record.billy.content
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "nomad-a04" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "nomad"
  content = cloudflare_record.robert.content
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "wildcardmad-a01" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "*"
  content = cloudflare_record.jerry.content
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "wildcardmad-a02" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "*"
  content = cloudflare_record.bobby.content
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "wildcardmad-a03" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "*"
  content = cloudflare_record.robert.content
  type    = "A"
  proxied = false
  allow_overwrite = true
}
