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

resource "nomad_variable" "postgres_backup_password" {
  path = "nomad/jobs/postgres-backup"
  items = {
    postgres_password = data.onepassword_item.postgres_pass.password
  }
}

data "template_file" "octant_backup" {
  template = "${file("./octant-backup.nomad.hcl")}"
  vars = {
    region = var.region
    datacenter = var.datacenter
  }
}

# Register Octant backup job
resource "nomad_job" "octant_backup" {
  jobspec = "${data.template_file.octant_backup.rendered}"
}