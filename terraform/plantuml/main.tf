# Configure the Nomad provider
provider "nomad" {
  address = "http://${var.nomad}:4646"
}

# Configure the Consul provider
provider "consul" {
  address = "http://${var.consul}:8500"
}


data "template_file" "plantuml_template" {
  template = "${file("./plantuml.nomad.hcl")}"
  vars = {
    region = var.region
    datacenter = var.datacenter
    image = var.image
  }
}

# Register job
resource "nomad_job" "plantuml" {
  jobspec = "${data.template_file.plantuml_template.rendered}"
}