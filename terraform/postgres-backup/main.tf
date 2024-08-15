# Configure the Nomad provider
provider "nomad" {
  address = "http://${var.nomad}:4646"
}

# Configure the Consul provider
provider "consul" {
  address = "http://${var.consul}:8500"
}

data "nomad_allocations" "postgres" {
  filter = "Name == \"postgres.db[0]\" and ClientStatus == \"running\""
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
    datacenter = var.datacenter
  }
}

# Register postgres backup job
resource "nomad_job" "postgres_backup" {
  depends_on = [consul_keys.postgres_alloc]
  jobspec = "${data.template_file.postgres_backup.rendered}"
}