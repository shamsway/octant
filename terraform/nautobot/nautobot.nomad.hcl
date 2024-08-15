job "nautobot" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  # Adjust as needed for rootless/root containers
  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }

  group "nautobot" {
    network {
      port "http" {
        to = 8000 
      }

      port "https" {
        to = 8443 
      }

      dns {
        servers = ${dns}
      }      
    }

    volume "nautobot-config" {
      type      = "host"
      read_only = false
      source    = "nautobot-config"
    }

    service {
      nname = "${servicename}"
      task = "nautobot"
      provider = "consul"
      port = "http"
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
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "nautobot" {
      driver = "podman"
      user = "nautobot"

      config {
        image = "${image}"
        ports = ["http","https"]
        volumes = ["local/uwsgi.ini:/opt/nautobot/uwsgi.ini","secrets/nautobot_config.py:/opt/nautobot/nautobot_config.py"]
        userns = "keep-id:uid=999,gid=999"
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "${servicename}"
            }
          ]
        }         
      }

      volume_mount {
        volume      = "nautobot-config"
        destination = "/opt/nautobot/"
        read_only   = false
      }

      env {
        NAUTOBOT_CREATE_SUPERUSER=true
        NAUTOBOT_SUPERUSER_EMAIL="${nautobot_superuser_email}"
        NAUTOBOT_REDIS_HOST="${redis_host}"
        NAUTOBOT_REDIS_PORT=6379
        NAUTOBOT_CACHEOPS_REDIS="redis://${redis_host}:6379/1"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/nautobot" -}}
NAUTOBOT_SUPERUSER_NAME={{ .nautobot_username }}
NAUTOBOT_SUPERUSER_PASSWORD={{ .nautobot_password }}
NAUTOBOT_SUPERUSER_API_TOKEN={{ .nautobot_api_key }}
{{- end -}}
EOT
      }

      template {
        destination = "$${NOMAD_TASK_DIR}/uwsgi.ini"
        data = base64decode("${uwsgi_ini}")
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/nautobot_config.py"
        data = base64decode("${nautobot_config}")
      }

      resources {
        memory = 384
      }
    }
  }
}