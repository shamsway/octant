job "ceph-csi-controller" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "false"
  }

  group "controller" {
    network {
      port "metrics" {}
    }

    task "ceph-controller" {
      driver = "docker"

      config {
        image = "${csi_image}"

        args = [
          "--type=rbd",
          "--controllerserver=true",
          "--drivername=rbd.csi.ceph.com",
          "--endpoint=unix://csi/csi.sock",
          "--nodeid=$${node.unique.name}",
          "--instanceid=$${NOMAD_ALLOC_ID}",
          "--logtostderr=true",
          "--v=5",
        ]

        volumes = [
          "./local/config.json:/etc/ceph-csi-config/config.json",
        ]

        mounts = [
          {
            type     = "tmpfs"
            target   = "/tmp/csi/keys"
            readonly = false
            tmpfs_options = {
              size = 1000000
            }
          }
        ]
      }

      template {
        data = <<-EOF
        ${ceph_config_json}
        EOF

        destination = "local/config.json"
        change_mode = "noop"
      }

      csi_plugin {
        id        = "ceph-csi"
        type      = "controller"
        mount_dir = "/csi"
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }
  }
}
