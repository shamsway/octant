terraform {
  required_providers {
    onepassword = {
      source = "1Password/onepassword"
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

# Configure 1password provider
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

resource "nomad_variable" "postgres_backup_password" {
  path = "nomad/jobs/postgres-backup"
  items = {
    postgres_password = data.onepassword_item.postgres_pass.password
  }
}

data "template_file" "octant_backup" {
  template = "${file("./octant-backup.nomad.hcl")}"
  vars = {
    region = var.region
    datacenter = var.datacenter
  }
}

# Register Octant backup job
resource "nomad_job" "octant_backup" {
  jobspec = "${data.template_file.octant_backup.rendered}"
}
