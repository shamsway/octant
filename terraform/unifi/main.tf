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
  }
}

# Register job
resource "nomad_job" "unifi" {
  jobspec = "${data.template_file.unifi_job_template.rendered}"
}