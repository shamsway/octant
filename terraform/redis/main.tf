# Configure the Nomad provider
provider "nomad" {
  address = "http://${var.nomad}:4646"
}

data "template_file" "redis_template" {
  template = "${file("./redis.nomad.hcl")}"
  vars = {
    region = var.region
    datacenter = var.datacenter
    image = var.image
  }
}

# Register job
resource "nomad_job" "job_name" {
  jobspec = "${data.template_file.redis_template.rendered}"
}