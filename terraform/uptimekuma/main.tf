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

provider "onepassword" {
  # Authenticates via OP_SERVICE_ACCOUNT_TOKEN environment variable
}

data "onepassword_vault" "vault" {
  name = var.op_vault_name
}

data "onepassword_item" "uptimekuma_db" {
  vault = data.onepassword_vault.vault.uuid
  title = "db_uptimekuma"
}

resource "nomad_variable" "uptimekuma_secrets" {
  path = "nomad/jobs/uptimekuma"
  items = {
    db_username = data.onepassword_item.uptimekuma_db.username
    db_password = data.onepassword_item.uptimekuma_db.password
  }
}

resource "nomad_job" "uptimekuma" {
  jobspec = templatefile("${path.module}/uptimekuma.nomad.hcl", {
    region       = var.region
    datacenter   = var.datacenter
    image        = var.image
    domain       = var.domain
    certresolver = var.certresolver
    servicename  = var.servicename
    dns          = jsonencode(var.dns)
    mariadb_host = var.mariadb_host
    mariadb_db   = var.mariadb_db
  })
  depends_on = [nomad_variable.uptimekuma_secrets]
}
