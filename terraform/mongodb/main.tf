terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 2.1.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

resource "random_password" "mongodb_keyfile" {
  length  = 756
  special = false
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

data "onepassword_item" "mongodb_root" {
  vault = data.onepassword_vault.vault.uuid
  title = "service_mongodb"
}

resource "nomad_variable" "mongodb" {
  path = "nomad/jobs/mongodb"
  items = {
    root_username  = data.onepassword_item.mongodb_root.username
    root_password  = data.onepassword_item.mongodb_root.password
    keyfile_secret = random_password.mongodb_keyfile.result
  }
}

resource "nomad_job" "mongodb" {
  for_each = var.members
  jobspec = templatefile("${path.module}/mongodb.nomad.hcl", {
    region      = var.region
    datacenter  = var.datacenter
    image       = var.image
    dns         = jsonencode(var.dns)
    servicename = each.key
    node_name   = each.value.node
    is_primary  = each.key == "mongodb-1"
  })
  depends_on = [nomad_variable.mongodb]
}
