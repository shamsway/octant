job "n8n" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "true"
  }

  group "n8n" {
    network {
      port "http" {
        static = 5678
        to     = 5678
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      port     = "http"

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${servicename}.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}.tls.certresolver=${certresolver}",
        "traefik.http.routers.${servicename}.middlewares=redirect-web-to-websecure@internal",
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/healthz/readiness"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "n8n" {
      driver = "podman"
      user   = "1000"

      config {
        image              = "${image}"
        ports              = ["http"]
        image_pull_timeout = "15m"
        userns             = "keep-id:uid=1000,gid=1000"
        volumes = [
          "/mnt/services/n8n/config:/home/node/.n8n",
          "/mnt/services/n8n/data:/data",
        ]
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
        N8N_HOST             = "${n8n_host}"
        N8N_PUBLIC_URL       = "${n8n_public_url}"
        N8N_PORT             = "5678"
        N8N_PROTOCOL         = "http"
        DB_TYPE              = "postgresdb"
        DB_POSTGRESDB_HOST   = "${postgres_host}"
        DB_POSTGRESDB_PORT   = "5432"
        DB_POSTGRESDB_DATABASE = "${postgres_db}"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/n8n" -}}
DB_POSTGRESDB_USER="{{ .n8n_postgres_user }}"
DB_POSTGRESDB_PASSWORD="{{ .n8n_postgres_password }}"
N8N_BASIC_AUTH_USER="{{ .n8n_admin_username }}"
N8N_BASIC_AUTH_PASSWORD="{{ .n8n_admin_password }}"
{{- end -}}
EOT
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
