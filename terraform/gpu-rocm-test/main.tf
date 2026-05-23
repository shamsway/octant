provider "nomad" {
  address = "http://${var.nomad}:4646"
}

resource "nomad_job" "gpu-rocm-test" {
  jobspec = templatefile("${path.module}/gpu-rocm-test.nomad.hcl", {
    region     = var.region
    datacenter = var.datacenter
    image      = var.image
  })
}
