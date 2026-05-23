terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 2.1.2"
    }
  }
}

provider "nomad" {
  address = "http://${var.nomad}:4646"
}

provider "consul" {
  address = "http://${var.consul}:8500"
}

provider "onepassword" {
  # Authenticates via OP_SERVICE_ACCOUNT_TOKEN environment variable
}

data "onepassword_vault" "vault" {
  name = var.op_vault_name
}

data "onepassword_item" "postgres_pass" {
  vault = data.onepassword_vault.vault.uuid
  title = "service_postgres"
}

resource "nomad_variable" "postgres_password" {
  path = "nomad/jobs/postgres"
  items = {
    postgres_password = data.onepassword_item.postgres_pass.password
  }
}

resource "nomad_variable" "postgres_backup_password" {
  path = "nomad/jobs/postgres-backup"
  items = {
    postgres_password = data.onepassword_item.postgres_pass.password
  }
}

resource "nomad_job" "postgres" {
  jobspec = templatefile("${path.module}/postgres.nomad.hcl", {
    region      = var.region
    datacenter  = var.datacenter
    image       = var.image
    dns         = jsonencode(var.dns)
    servicename = var.servicename
    node_name   = var.node_name
  })
  depends_on = [nomad_variable.postgres_password]
}
