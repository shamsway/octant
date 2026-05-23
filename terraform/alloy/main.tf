provider "nomad" {
  address = "http://${var.nomad}:4646"
}

data "local_file" "alloy_config" {
  filename = "${path.module}/config.alloy"
}

resource "nomad_job" "alloy" {
  jobspec = templatefile("${path.module}/alloy.nomad.hcl", {
    region       = var.region
    datacenter   = var.datacenter
    image        = var.image
    dns          = jsonencode(var.dns)
    servicename  = var.servicename
    config_alloy = data.local_file.alloy_config.content
  })
}
