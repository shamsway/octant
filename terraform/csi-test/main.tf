provider "nomad" {
  address = "http://${var.nomad}:4646"
}

resource "nomad_job" "csi_test" {
  jobspec = templatefile("${path.module}/csi-test.nomad.hcl", {
    region     = var.region
    datacenter = var.datacenter
    dns        = jsonencode(var.dns)
  })
}
