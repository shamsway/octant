provider "nomad" {
  address = "http://${var.nomad}:4646"
}

locals {
  ceph_config_json = jsonencode([{
    clusterID = var.ceph_fsid
    monitors  = var.ceph_monitors
  }])
}

resource "nomad_job" "ceph_csi_controller" {
  jobspec = templatefile("${path.module}/ceph-csi-controller.nomad.hcl", {
    region           = var.region
    datacenter       = var.datacenter
    csi_image        = var.csi_image
    ceph_config_json = local.ceph_config_json
  })
}

resource "nomad_job" "ceph_csi_node" {
  jobspec = templatefile("${path.module}/ceph-csi-node.nomad.hcl", {
    region           = var.region
    datacenter       = var.datacenter
    csi_image        = var.csi_image
    ceph_config_json = local.ceph_config_json
  })

  depends_on = [nomad_job.ceph_csi_controller]
}
