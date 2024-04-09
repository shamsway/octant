id        = "ceph-acme-vol"
name      = "ceph-acme-vol"
type      = "csi"
plugin_id = "ceph"

capacity_min = "10MB"
capacity_max = "20MB"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "block-device"
}

secrets {
  userID  = "admin"
  userKey = "AQA9GwtmtT92GhAAqW1Ire/P+guqXIRACC6gcQ=="
}

parameters {
  clusterID     = "12cffc86-f032-11ee-8cdf-000c2961913e"
  pool          = "rbd"
  imageFeatures = "layering"
  mkfsOptions   = "-t ext4"  
}