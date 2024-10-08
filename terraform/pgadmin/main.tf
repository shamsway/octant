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
  url                   = "${var.op_api_url}"
  token                 = "${var.OP_API_TOKEN}"
  op_cli_path           = "/usr/local/bin/op"
}

data "onepassword_vault" "dev" {
  name = "Dev"
}

data "onepassword_item" "postgres_pass" {
  vault = data.onepassword_vault.dev.uuid
  title = "Postgres"
}

data "template_file" "pgadmin" {
  template = "${file("./pgadmin.nomad.hcl")}"
  vars = {
    region = var.region
    shared_dir = var.shared_dir
    datacenter = var.datacenter
    image = var.image
    domain = var.domain
    certresolver = var.certresolver
    servicename = var.servicename
    dns = jsonencode(var.dns)    
    pgadmin_email = var.pgadmin_email
  }
}

# Register postgres job
resource "nomad_job" "pgadmin" {
  jobspec = "${data.template_file.pgadmin.rendered}"
}