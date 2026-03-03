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

data "onepassword_item" "mariadb_root" {
  vault = data.onepassword_vault.vault.uuid
  title = "service_mariadb"
}

resource "nomad_variable" "mariadb" {
  path = "nomad/jobs/mariadb"
  items = {
    root_password = data.onepassword_item.mariadb_root.password
  }
}

resource "nomad_job" "mariadb" {
  jobspec    = templatefile("${path.module}/mariadb.nomad.hcl", {
    region      = var.region
    datacenter  = var.datacenter
    image       = var.image
    dns         = jsonencode(var.dns)
    servicename = var.servicename
  })
  depends_on = [nomad_variable.mariadb]
}
