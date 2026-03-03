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

data "onepassword_item" "postgres_pass" {
  vault = data.onepassword_vault.vault.uuid
  title = "service_postgres"
}

resource "nomad_variable" "pgadmin" {
  path = "nomad/jobs/pgadmin"
  items = {
    postgres_password = data.onepassword_item.postgres_pass.password
  }
}

resource "nomad_job" "pgadmin" {
  jobspec = templatefile("${path.module}/pgadmin.nomad.hcl", {
    region        = var.region
    datacenter    = var.datacenter
    image         = var.image
    domain        = var.domain
    certresolver  = var.certresolver
    servicename   = var.servicename
    dns           = jsonencode(var.dns)
    pgadmin_email = var.pgadmin_email
  })
  depends_on = [nomad_variable.pgadmin]
}
