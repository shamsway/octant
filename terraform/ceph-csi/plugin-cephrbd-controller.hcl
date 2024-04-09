job "csi-ceph" {
  datacenters = ["shamsway"]

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  type = "service"

  group "csi-ceph" {

    network {
      port "prometheus" {}
    }

    service {
      name = "csi-ceph"
      port = "prometheus"
      tags = ["csi-ceph"]
    }

    task "plugin" {
      driver = "docker"

      config {
        image = "quay.io/cephcsi/cephcsi:v3.10.2"

        args = [
          "--drivername=rbd.csi.ceph.com",
          "--v=5",
          "--type=rbd",
          "--controllerserver=true",
          "--nodeid=${NODE_ID}",
          "--instanceid=${POD_ID}",
          "--endpoint=${CSI_ENDPOINT}",
          "--metricsport=${NOMAD_PORT_prometheus}",
        ]

        ports = ["prometheus"]
        mounts = [
          {
            type     = "tmpfs"
            target   = "/tmp/csi/keys"
            readonly = false
            tmpfs_options = {
              size = 1000000 # size in bytes
            }
          }
        ]
        # we need to be able to write key material to disk in this location
        volumes = ["local/config.json:/etc/ceph-csi-config/config.json"]
      }

      template {
        data = <<-EOT
POD_ID=${NOMAD_ALLOC_ID}
NODE_ID=${node.unique.id}
CSI_ENDPOINT=unix://csi/csi.sock
EOT

        destination = "${NOMAD_TASK_DIR}/env"
        env         = true
      }

      # ceph configuration file
      template {

        data = <<EOF
[{
    "clusterID": "bd6dc076-f0e9-11ee-8cdf-000c2961913e",
    "monitors": [
        "192.168.252.6", "192.168.252.7", "192.168.252.8"
    ]
}]
EOF

        destination = "local/config.json"
      }

      csi_plugin {
        id        = "ceph"
        type      = "controller"
        mount_dir = "/csi"
      }

      # note: there's no upstream guidance on resource usage so
      # this is a best guess until we profile it in heavy use
      resources {
        cpu    = 256
        memory = 256
      }
    }
  }
}