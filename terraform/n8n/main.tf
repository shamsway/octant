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

data "onepassword_item" "postgres_n8n" {
  vault = data.onepassword_vault.vault.uuid
  title = "db_n8n"
}

data "onepassword_item" "n8n_admin" {
  vault = data.onepassword_vault.vault.uuid
  title = "service_n8n"
}

resource "nomad_variable" "n8n_secrets" {
  path = "nomad/jobs/n8n"
  items = {
    n8n_postgres_user     = data.onepassword_item.postgres_n8n.username
    n8n_postgres_password = data.onepassword_item.postgres_n8n.password
    n8n_admin_username    = data.onepassword_item.n8n_admin.username
    n8n_admin_password    = data.onepassword_item.n8n_admin.password
  }
}

resource "nomad_job" "n8n" {
  jobspec = templatefile("${path.module}/n8n.nomad.hcl", {
    region       = var.region
    datacenter   = var.datacenter
    image        = var.n8n_image
    domain       = var.domain
    certresolver = var.certresolver
    servicename  = var.servicename
    dns          = jsonencode(var.dns)
    postgres_host = var.postgres_host
    postgres_db   = var.postgres_db
    n8n_host      = var.n8n_host
    n8n_public_url = var.n8n_public_url
  })
  depends_on = [nomad_variable.n8n_secrets]
}
