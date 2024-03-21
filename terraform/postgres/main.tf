locals {
  config = yamldecode(file(var.inventory_vars))
  #inventory = yamldecode(file(var.inventory))
}

# Configure the Nomad provider
provider "nomad" {
  address = "http://${var.nomad}:4646"
}

data "template_file" "job" {
  template = "${file("./postgres.hcl.tmpl")}"
  vars = {
    region = var.region
    shared_dir = var.shared_dir
    datacenter = local.config.datacenter
    image = var.image
    postgres_password = var.postgres_password
  }
}

# Register a job
resource "nomad_job" "postgres" {
  jobspec = "${data.template_file.job.rendered}"
}
