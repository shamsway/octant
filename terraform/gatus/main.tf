provider "nomad" {
  address = "http://${var.nomad}:4646"
}

data "local_file" "gatus_config" {
  filename = "${path.module}/config.yaml"
}

resource "nomad_job" "gatus" {
  jobspec = templatefile("${path.module}/gatus.nomad.hcl", {
    region       = var.region
    datacenter   = var.datacenter
    image        = var.image
    domain       = var.domain
    certresolver = var.certresolver
    servicename  = var.servicename
    dns          = jsonencode(var.dns)
    config_yaml  = data.local_file.gatus_config.content
  })
}
