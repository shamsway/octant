provider "nomad" {
  address = "http://${var.nomad}:4646"
}

provider "consul" {
  address = "http://${var.consul}:8500"
}

resource "nomad_job" "qdrant" {
  jobspec = templatefile("${path.module}/qdrant.nomad.hcl", {
    region       = var.region
    datacenter   = var.datacenter
    domain       = var.domain
    certresolver = var.certresolver
    servicename  = var.servicename
    dns          = jsonencode(var.dns)
    image        = var.image
  })
}
