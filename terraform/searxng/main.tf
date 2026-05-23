provider "nomad" {
  address = "http://${var.nomad}:4646"
}

provider "consul" {
  address = "http://${var.consul}:8500"
}

resource "nomad_job" "searxng" {
  jobspec = templatefile("${path.module}/searxng.nomad.hcl", {
    region        = var.region
    datacenter    = var.datacenter
    domain        = var.domain
    certresolver  = var.certresolver
    servicename   = var.servicename
    dns           = var.dns
    searxng_image = var.searxng_image
    redis_image   = var.redis_image
    uwsgi_workers = var.uwsgi_workers
    uwsgi_threads = var.uwsgi_threads
  })
}
