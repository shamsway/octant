terraform {
  required_providers {
    onepassword = {
      source = "1Password/onepassword"
      version = "~> 1.3.0"
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
  url                   = "https://opapi.shamsway.net"
  token                 = "${var.OP_API_TOKEN}"
  op_cli_path           = "/usr/local/bin/op"
}

data "onepassword_vault" "dev" {
  name = "Dev"
}

data "onepassword_item" "postgres_pass" {
  vault = data.onepassword_vault.dev.uuid
  title = "Postgres"
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
  template = "${file("./postgres.hcl")}"
  vars = {
    region = var.region
    shared_dir = var.shared_dir
    datacenter = var.datacenter
    image = var.image
    pgadmin_email = var.pgadmin_email
  }
}

# Register postgres job
resource "nomad_job" "postgres" {
  jobspec = "${data.template_file.postgres.rendered}"
}

data "nomad_allocations" "postgres" {
  depends_on = [nomad_job.postgres]
  filter = "JobID == \"${nomad_job.postgres.id}\" and ClientStatus == \"running\""
}

# Save job ID to Consul KV store
resource "consul_keys" "postgres_alloc" {
  key {
    path  = "service/postgres/alloc"
    value = "${data.nomad_allocations.postgres.allocations[0].id}"
  }
}

data "template_file" "postgres_backup" {
  template = "${file("./postgres-backup.nomad.hcl")}"
  vars = {
    region = var.region
    datacenter = local.config.datacenter
  }
}

# Register postgres backup job
resource "nomad_job" "postgres_backup" {
  depends_on = [consul_keys.postgres_alloc]
  jobspec = "${data.template_file.postgres_backup.rendered}"
}