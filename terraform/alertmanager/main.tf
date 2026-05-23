provider "nomad" {
  address = "http://${var.nomad}:4646"
}

data "local_file" "alertmanager_config" {
  filename = "${path.module}/alertmanager.yml"
}

resource "nomad_job" "alertmanager" {
  jobspec = templatefile("${path.module}/alertmanager.nomad.hcl", {
    region       = var.region
    datacenter   = var.datacenter
    image        = var.image
    domain       = var.domain
    certresolver = var.certresolver
    servicename  = var.servicename
    dns          = jsonencode(var.dns)
    config_yaml  = data.local_file.alertmanager_config.content
  })
}
