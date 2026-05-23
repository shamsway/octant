id        = "postgres-data"
name      = "postgres-data"
type      = "csi"
plugin_id = "ceph-csi"

capacity_min = "5GiB"
capacity_max = "5GiB"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

secrets {
  userID  = "nomad-csi"
  userKey = "AQCAUKtp2aBQIhAAMHNNXAyyNup+T+eeU3r5mw=="
}

parameters {
  clusterID     = "c2ea7540-11d9-11f1-8256-525400000101"
  pool          = "nomad-csi"
  imageFeatures = "layering"
  mkfsOptions   = "-t ext4"
}
