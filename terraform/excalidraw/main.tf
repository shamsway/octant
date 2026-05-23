# Configure the Nomad provider
provider "nomad" {
  address = "http://${var.nomad}:4646"
}

resource "nomad_job" "excalidraw" {
  jobspec = templatefile("${path.module}/excalidraw.nomad.hcl", {
    region       = var.region
    datacenter   = var.datacenter
    image        = var.image
    domain       = var.domain
    certresolver = var.certresolver
    servicename  = var.servicename
    dns          = jsonencode(var.dns)
  })
}
