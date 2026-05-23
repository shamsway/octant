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

data "nomad_allocations" "mariadb" {
  filter = "Name == \"mariadb.mariadb[0]\" and ClientStatus == \"running\""
}

resource "consul_keys" "mariadb_alloc" {
  count = length(data.nomad_allocations.mariadb.allocations) > 0 ? 1 : 0
  key {
    path  = "service/mariadb/alloc"
    value = data.nomad_allocations.mariadb.allocations[0].id
  }
}

resource "nomad_job" "mariadb_backup" {
  depends_on = [consul_keys.mariadb_alloc]
  jobspec    = templatefile("${path.module}/mariadb-backup.nomad.hcl", {
    region     = var.region
    datacenter = var.datacenter
  })
}
