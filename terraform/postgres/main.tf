terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 2.1.2"
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

# Configure 1password provider (SaaS via op CLI)
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

data "template_file" "postgres" {
  template = "${file("./postgres.nomad.hcl")}"
  vars = {
    region      = var.region
    shared_dir  = var.shared_dir
    datacenter  = var.datacenter
    image       = var.image
    domain      = var.domain
    certresolver = var.certresolver
    servicename = var.servicename
    dns         = jsonencode(var.dns)
  }
}

# Register postgres job
resource "nomad_job" "postgres" {
  jobspec = "${data.template_file.postgres.rendered}"
}
