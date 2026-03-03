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

provider "consul" {
  address = "http://${var.consul}:8500"
}

provider "onepassword" {}

data "onepassword_vault" "vault" {
  name = "Octant"
}

data "onepassword_item" "postgres" {
  vault = data.onepassword_vault.vault.uuid
  title = "service_postgres"
}

data "nomad_allocations" "postgres" {
  filter = "Name == \"postgres.postgres[0]\" and ClientStatus == \"running\""
}

resource "consul_keys" "postgres_alloc" {
  key {
    path  = "service/postgres/alloc"
    value = data.nomad_allocations.postgres.allocations[0].id
  }
}

resource "nomad_variable" "postgres_backup" {
  path = "nomad/jobs/postgres-backup"
  items = {
    postgres_password = data.onepassword_item.postgres.password
  }
}

resource "nomad_job" "postgres_backup" {
  depends_on = [consul_keys.postgres_alloc, nomad_variable.postgres_backup]
  jobspec    = templatefile("${path.module}/postgres-backup.nomad.hcl", {
    region     = var.region
    datacenter = var.datacenter
  })
}
