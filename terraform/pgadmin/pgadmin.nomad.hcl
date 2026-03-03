  # terraform apply -auto-approve
  # terraform destroy -auto-approve

job "pgadmin" {
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

  group "pgadmin" {
    count = 1

    network {
      port "pgadmin" {
        to = 80
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      task     = "pgadmin"
      port     = "pgadmin"

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${servicename}.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}.tls.certresolver=${certresolver}",
        "traefik.http.routers.${servicename}.middlewares=redirect-web-to-websecure@internal",
      ]

      connect {
        native = true
      }

      check {
        name     = "alive"
        type     = "http"
        path     = "/"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "pgadmin" {
      driver = "podman"
      user   = "5050"

      config {
        image              = "${image}"
        ports              = ["pgadmin"]
        image_pull_timeout = "15m"
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "${servicename}"
            }
          ]
        }
      }

      env {
        PGADMIN_DEFAULT_EMAIL    = "${pgadmin_email}"
        PGADMIN_LISTEN_ADDRESS   = "0.0.0.0"
        PGADMIN_DISABLE_POSTFIX  = "true"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{ with nomadVar "nomad/jobs/pgadmin" }}PGADMIN_DEFAULT_PASSWORD={{ .postgres_password }}{{ end }}
EOT
      }

      resources {
        memory = 384
      }
    }
  }
}
