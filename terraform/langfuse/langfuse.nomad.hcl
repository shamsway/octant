job "langfuse" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }

  group "langfuse" {
    network {
      port "http" {
        to = 3000
      }

      dns {
        servers = ${dns}
      }         
    }

    service {
      name = "${servicename}"
      provider = "consul"
      port = "http"
      tags = [
        "traefik.enable=true",
		    "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${servicename}.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}.tls.certresolver=${certresolver}",
      ]

      connect {
        native = true
      }        

      check {
        name     = "alive"
        type     = "http"
        path     = "/api/public/health"
        interval = "60s"
        timeout  = "5s"
      }
    }       
    
    task "langfuse" {
      driver = "podman"

      config {
        image = "${image}"
        ports = ["http"]
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
        NEXTAUTH_URL = "${nextauth_url}"
        NEXTAUTH_SECRET = "${nextauth_secret}"
        SALT = "${salt}"
        TELEMETRY_ENABLED = "${telemetry_enabled}"
        LANGFUSE_ENABLE_EXPERIMENTAL_FEATURES = "${langfuse_enable_experimental_features}"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/langfuse" -}}
DATABASE_URL="postgresql://{{ .db_username }}:{{ .db_password }}@${db_server}:5432/${db_name}"
{{- end -}}
EOT
      }    

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}