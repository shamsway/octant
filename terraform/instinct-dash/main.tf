provider "nomad" {
  address = "http://${var.nomad}:4646"
}

resource "nomad_job" "instinct-dash" {
  jobspec = templatefile("${path.module}/instinct-dash.nomad.hcl", {
    region           = var.region
    datacenter       = var.datacenter
    image            = var.image
    domain           = var.domain
    certresolver     = var.certresolver
    servicename      = var.servicename
    dns              = jsonencode(var.dns)
    poll_interval_ms = var.poll_interval_ms
  })
}
