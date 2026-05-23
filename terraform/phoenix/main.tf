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

provider "onepassword" {}

data "onepassword_vault" "vault" {
  name = var.op_vault_name
}

data "onepassword_item" "db_phoenix" {
  vault = data.onepassword_vault.vault.uuid
  title = "db_phoenix"
}

resource "nomad_variable" "phoenix_secrets" {
  path = "nomad/jobs/phoenix"
  items = {
    phoenix_db_user     = data.onepassword_item.db_phoenix.username
    phoenix_db_password = data.onepassword_item.db_phoenix.password
  }
}

resource "nomad_job" "phoenix" {
  jobspec = templatefile("${path.module}/phoenix.nomad.hcl", {
    region        = var.region
    datacenter    = var.datacenter
    image         = var.image
    domain        = var.domain
    certresolver  = var.certresolver
    servicename   = var.servicename
    dns           = jsonencode(var.dns)
    postgres_host = var.postgres_host
    postgres_db   = var.postgres_db
  })
  depends_on = [nomad_variable.phoenix_secrets]
}
