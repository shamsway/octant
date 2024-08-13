# Configure the Nomad provider
provider "nomad" {
  address = "http://${var.nomad}:4646"
}

data "template_file" "unifi_job_template" {
  template = "${file("./unifi.nomad.hcl")}"
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
resource "nomad_job" "unifi" {
  jobspec = "${data.template_file.unifi_job_template.rendered}"
}