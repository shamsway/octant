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

data "onepassword_item" "mongodb_root" {
  vault = data.onepassword_vault.vault.uuid
  title = "service_mongodb"
}

resource "nomad_variable" "rocketchat" {
  path = "nomad/jobs/rocketchat"
  items = {
    mongo_username = data.onepassword_item.mongodb_root.username
    mongo_password = data.onepassword_item.mongodb_root.password
  }
}

resource "nomad_job" "rocketchat" {
  jobspec = templatefile("${path.module}/rocketchat.nomad.hcl", {
    region       = var.region
    datacenter   = var.datacenter
    image        = var.image
    domain       = var.domain
    certresolver = var.certresolver
    servicename  = var.servicename
    dns          = jsonencode(var.dns)
    mongo_hosts  = var.mongo_hosts
    mongo_db     = var.mongo_db
  })
  depends_on = [nomad_variable.rocketchat]
}
