job "ceph-csi-node" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "system"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "false"
  }

  group "nodes" {
    network {
      port "metrics" {}
    }

    task "ceph-node" {
      driver = "docker"

      config {
        image        = "${csi_image}"
        privileged   = true
        network_mode = "host"

        args = [
          "--type=rbd",
          "--nodeserver=true",
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
          },
          {
            type     = "bind"
            target   = "/sys"
            source   = "/sys"
            readonly = false
          },
          {
            type     = "bind"
            target   = "/lib/modules"
            source   = "/lib/modules"
            readonly = true
          },
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
        type      = "node"
        mount_dir = "/csi"
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }
  }
}
