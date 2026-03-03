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

data "onepassword_item" "api_sendgrid_key" {
  vault = data.onepassword_vault.vault.uuid
  title = "api_sendgrid_key"
}

resource "nomad_job" "ntfy" {
  jobspec = templatefile("${path.module}/ntfy.nomad.hcl", {
    region       = var.region
    datacenter   = var.datacenter
    image        = var.ntfy_image
    domain       = var.domain
    certresolver = var.certresolver
    servicename  = var.servicename
    dns          = jsonencode(var.dns)
    timezone     = var.timezone
    smtp_server  = var.smtp_server
    smtp_port    = var.smtp_port
    smtp_username = data.onepassword_item.api_sendgrid_key.username
    smtp_password = data.onepassword_item.api_sendgrid_key.password
  })
}
