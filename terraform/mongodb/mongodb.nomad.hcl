job "${servicename}" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${attr.kernel.name}"
    value     = "linux"
  }

  constraint {
    attribute = "$${meta.rootless}"
    value     = "false"
  }

  constraint {
    attribute = "$${node.unique.name}"
    value     = "${node_name}"
  }

  group "mongodb" {
    count = 1

    volume "mongodb-data" {
      type            = "csi"
      source          = "${servicename}-data"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    network {
      port "mongodb" {
        static = 27017
        to     = 27017
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      task     = "mongodb"
      port     = "mongodb"

      tags = [
        "alloc=$${NOMAD_ALLOC_ID}",
        "mongodb-replica-set=rs0",
%{ if is_primary ~}
        "homepage.group=Databases",
        "homepage.name=MongoDB",
        "homepage.icon=mongodb",
        "homepage.description=Document DB (rs0)",
%{ endif ~}
      ]

      check {
        name     = "alive"
        type     = "tcp"
        port     = "mongodb"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "keyfile-init" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      volume_mount {
        volume      = "mongodb-data"
        destination = "/data/db"
      }

      config {
        image   = "${image}"
        command = "bash"
        args    = ["-c", "echo \"$KEYFILE_CONTENT\" > /data/db/.keyfile && chmod 400 /data/db/.keyfile && chown 999:999 /data/db/.keyfile"]
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{ with nomadVar "nomad/jobs/mongodb" }}KEYFILE_CONTENT={{ .keyfile_secret }}{{ end }}
EOT
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    task "mongodb" {
      driver = "docker"

      volume_mount {
        volume      = "mongodb-data"
        destination = "/data/db"
      }

      config {
        image = "${image}"
        ports = ["mongodb"]

        args = [
          "mongod",
          "--replSet", "rs0",
          "--oplogSize", "128",
          "--bind_ip_all",
          "--keyFile", "/data/db/.keyfile"
        ]

        logging {
          type = "journald"
          config {
            tag = "${servicename}"
          }
        }
      }

      env {
        TZ = "America/New_York"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{ with nomadVar "nomad/jobs/mongodb" }}MONGO_INITDB_ROOT_USERNAME={{ .root_username }}
MONGO_INITDB_ROOT_PASSWORD={{ .root_password }}{{ end }}
EOT
      }

      resources {
        cpu    = 200
        memory = 1024
      }
    }
  }
}
