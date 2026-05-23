provider "nomad" {
  address = "http://${var.nomad}:4646"
}

resource "nomad_job" "loki" {
  jobspec = templatefile("${path.module}/loki.nomad.hcl", {
    region       = var.region
    datacenter   = var.datacenter
    image        = var.image
    domain       = var.domain
    certresolver = var.certresolver
    servicename  = var.servicename
    dns          = jsonencode(var.dns)
    node_name    = var.node_name
  })
}
