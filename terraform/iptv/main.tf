terraform {
  required_providers {
    onepassword = {
      source = "1Password/onepassword"
      version = "~> 1.3.0"
    }
  }
}

# Configure the Nomad provider
provider "nomad" {
  address = "http://${var.nomad}:4646"
}

# Configure the Consul provider
provider "consul" {
  address = "http://${var.consul}:8500"
}

# Configure 1password provider
provider "onepassword" {
  url                   = "https://opapi.shamsway.net"
  token                 = "${var.OP_API_TOKEN}"
  op_cli_path           = "/usr/local/bin/op"
}

data "onepassword_vault" "dev" {
  name = "Dev"
}

data "onepassword_item" "zap2it_creds" {
  vault = data.onepassword_vault.dev.uuid
  title = "zap2it"
}

resource "nomad_variable" "zap2it_creds" {
  path = "nomad/jobs/iptv-download-guides"
  items = {
    zap2it_username = data.onepassword_item.zap2it_creds.username
    zap2it_password = data.onepassword_item.zap2it_creds.password
  }
}

data "onepassword_item" "wireguard_config" {
  vault = data.onepassword_vault.dev.uuid
  title = "Wireguard_NY25"
}

resource "nomad_variable" "wireguard_config" {
  path = "nomad/jobs/iptv"
  items = {
    wireguard_config = data.onepassword_item.wireguard_config.note_value
  }
}

data "template_file" "iptv_template" {
  template = "${file("./iptv.nomad.hcl")}"
  vars = {
    region = var.region
    datacenter = var.datacenter
    tvh_image = var.tvh_image
    gluetun_image = var.gluetun_image
  }
}

data "template_file" "iptv_download_template" {
  template = "${file("./iptv-download-guides.nomad.hcl")}"
  vars = {
    region = var.region
    datacenter = var.datacenter
  }
}

# Register IPTV job
resource "nomad_job" "iptv" {
  depends_on = [nomad_variable.wireguard_config]    
  jobspec = "${data.template_file.iptv_template.rendered}"
}

# Register IPTV guide downloader job
resource "nomad_job" "iptv_download" {
  depends_on = [nomad_variable.zap2it_creds]    
  jobspec = "${data.template_file.iptv_download_template.rendered}"
}