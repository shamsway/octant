job "csi-ceph-node" {
  datacenters = ["shamsway"]

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  type = "system"

  group "csi-ceph-node" {

    network {
      port "prometheus" {}
    }

    service {
      name = "prometheus"
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
          "--nodeserver=true",
          "--nodeid=${node.unique.name}",
          "--instanceid=${node.unique.name}-nodes",
          "--endpoint=unix://csi/csi.sock",
          "--metricsport=${NOMAD_PORT_prometheus}",
          "--pidlimit=-1",
          "--logtostderr=true"
        ]

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

        volumes = ["local/config.json:/etc/ceph-csi-config/config.json"]
        privileged = true
        ports      = ["prometheus"]
      }

      template {
        data        = <<EOF
[{
    "clusterID": "bd6dc076-f0e9-11ee-8cdf-000c2961913e",
    "monitors": [
        "192.168.252.6", "192.168.252.7", "192.168.252.8"
    ]
}]
EOF
        destination = "local/config.json"
        change_mode = "restart"
      }

      csi_plugin {
        id        = "ceph"
        type      = "node"
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
