## Example
id        = "testvolume"
name      = "test1"
type      = "csi"
plugin_id = "cephrbd"

capacity_min = "100MB"
capacity_max = "1GB"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "block-device"
}

# mount_options {
#   fs_type     = "ext4"
#   mount_flags = ["ro"]
# }


# creds should be coming from:
# /var/lib/ceph/mds/ceph-demo/keyring

# but instead we're getting them from:
# /etc/ceph/ceph.client.admin.keyring

secrets {
  userID  = "admin"
  userKey = "AQDsIoxgHqpeBBAAtmd9Ndu4m1xspTbvwZdIzA=="
}

parameters {
  # seeded from uuid5(ceph.example.com)
  clusterID     = "e9ba69fa-67ff-5920-b374-84d5801edd19"
  pool          = "rbd"
  imageFeatures = "layering"
}

## Example

id = "ceph-mysql"
name = "ceph-mysql"
type = "csi"
plugin_id = "ceph-csi"
capacity_max = "200G"
capacity_min = "100G"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

secrets {
  userID  = "admin"
  userKey = "AQAlh9Rgg2vrDxAARy25T7KHabs6iskSHpAEAQ=="
}

parameters {
  clusterID = "b9127830-b0cc-4e34-aa47-9d1a2e9949a8"
  pool = "nomad"
  imageFeatures = "layering"
  mkfsOptions = "-t ext4"
}

## Example

id = "ceph-mysql"
name = "ceph-mysql"
type = "csi"
plugin_id = "ceph-csi"
capacity_max = "200G"
capacity_min = "100G"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}

secrets {
  userID  = "admin"
  userKey = "AQAVXIlgv6krBhAATxGcAZZgOwW7mW9HdSPJxQ=="
}

parameters {
  clusterID = "e585be01-47aa-44bc-9a58-55415b3f4225"
  pool = "rbd"
  imageFeatures = "layering"
}