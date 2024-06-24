# Configure the Nomad provider
provider "nomad" {
  address = "http://${var.nomad}:4646"
}

data "template_file" "jupyter_template" {
  template = "${file("./jupyter.nomad.hcl")}"
  vars = {
    region = var.region
    datacenter = var.datacenter
    image = var.image
  }
}

# Register job
resource "nomad_job" "jupyter" {
  jobspec = "${data.template_file.jupyter_template.rendered}"
}