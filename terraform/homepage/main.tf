provider "nomad" {
  address = "http://${var.nomad}:4646"
}

resource "nomad_job" "homepage" {
  jobspec = templatefile("${path.module}/homepage.nomad.hcl", {
    region       = var.region
    datacenter   = var.datacenter
    image        = var.image
    domain       = var.domain
    certresolver = var.certresolver
    servicename  = var.servicename
    dns          = jsonencode(var.dns)
  })
}
