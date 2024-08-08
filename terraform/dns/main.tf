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
  default = "shamsway.net"
}

data "cloudflare_zones" "domain" {
  filter {
    name = var.domain_name
  }
}

resource "cloudflare_record" "edgerouter" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "edgerouter"
  value   = "192.168.252.1"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "joan" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "joan"
  value   = "192.168.252.5"
  type    = "A"
  proxied = false
  allow_overwrite = false
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

resource "cloudflare_record" "nfs" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "nfs"
  value   = "192.168.252.9"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "robert" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "robert"
  value   = "192.168.252.10"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "basementswitch" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "basementswitch"
  value   = "192.168.252.11"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "officeswitch" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "officeswitch"
  value   = "192.168.252.12"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "basementap" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "basementap"
  value   = "192.168.252.13"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "officeap" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "officeap"
  value   = "192.168.252.14"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "lrtv" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "lrtv"
  value   = "192.168.252.15"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "basementtv" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "basementtv"
  value   = "192.168.252.16"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "bedroomtv" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "bedroomtv"
  value   = "192.168.252.17"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "audreytv" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "audreytv"
  value   = "192.168.252.18"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "lextv" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "lextv"
  value   = "192.168.252.19"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "printer" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "printer"
  value   = "192.168.252.20"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "desklight" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "desklight"
  value   = "192.168.252.21"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "tuneslight" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "tuneslight"
  value   = "192.168.252.22"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "mediapi" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "mediapi"
  value   = "192.168.252.23"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "macbook" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "macbook"
  value   = "192.168.252.30"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "cablight1" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "cablight1"
  value   = "192.168.252.194"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "cablight2" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "cablight2"
  value   = "192.168.252.157"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "lrlight" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "lrlight"
  value   = "192.168.252.234"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "matrixlight" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "matrixlight"
  value   = "192.168.252.157"
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "tvlight" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "tvlight"
  value   = "192.168.252.237"
  type    = "A"
  proxied = false
  allow_overwrite = false
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
  allow_overwrite = false
}

resource "cloudflare_record" "consul-a02" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "consul"
  value   = cloudflare_record.bobby.value
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "consul-a03" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "consul"
  value   = cloudflare_record.billy.value
  type    = "A"
  proxied = false
  allow_overwrite = false
}

resource "cloudflare_record" "consul-a04" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "consul"
  value   = cloudflare_record.robert.value
  type    = "A"
  proxied = false
  allow_overwrite = false
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

resource "cloudflare_record" "nomad-a03" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "nomad"
  value   = cloudflare_record.billy.value
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "nomad-a04" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "nomad"
  value   = cloudflare_record.robert.value
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
  value   = cloudflare_record.robert.value
  type    = "A"
  proxied = false
  allow_overwrite = true
}