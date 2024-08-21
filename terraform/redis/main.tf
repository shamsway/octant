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
    domain = var.domain
    certresolver = var.certresolver
    servicename = var.servicename
    dns = jsonencode(var.dns)    
  }
}

# Register job
resource "nomad_job" "job_name" {
  jobspec = "${data.template_file.redis_template.rendered}"
}