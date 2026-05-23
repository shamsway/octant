provider "nomad" {
  address = "http://${var.nomad}:4646"
}

resource "nomad_job" "gpu-pytorch-test" {
  jobspec = templatefile("${path.module}/gpu-pytorch-test.nomad.hcl", {
    region     = var.region
    datacenter = var.datacenter
    image      = var.image
  })
}
