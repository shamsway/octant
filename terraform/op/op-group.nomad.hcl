job "op-connect" {
  datacenters = ["shamsway"]
  type = "service"

  constraint {
      attribute = "${meta.rootless}"
      value     = "true"
  }

  affinity {
    attribute = "${meta.class}"
    value     = "physical"
    weight    = 100
  }

  group "op-connect" {
    network {
      port "opapi" {
        to = 8080
      }

      port "opsync" {
        to = 8081
      }

      port "opapibus" {
        static = 11223
        to = 11223
      }

      port "opsyncbus" {
        static = 11224
        to = 11224
      }

      dns {
        servers = ["192.168.252.1","192.168.252.6","192.168.252.7"]
      }
    }

    service {
      name = "opapi"
      provider = "consul"
      port = "opapi"
      task = "opapi"
      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.opapi.rule=Host(`opapi.shamsway.net`)",
        "traefik.http.routers.opapi.entrypoints=web,websecure",
        "traefik.http.routers.opapi.tls.certresolver=cloudflare",
        "traefik.http.routers.opapi.middlewares=redirect-web-to-websecure@internal",
      ]

      connect {
        native = true
      }

      check {
        name     = "alive"
        type     = "http"
        path     = "/health"
        interval = "30s"
        timeout  = "5s"
      }
    }

    service {
      name = "opsync"
      provider = "consul"
      port = "opsync"
      task = "opsync"      
      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.opsync.rule=Host(`opsync.shamsway.net`)",
        "traefik.http.routers.opsync.entrypoints=web,websecure",
        "traefik.http.routers.opsync.tls.certresolver=cloudflare",
        "traefik.http.routers.opsync.middlewares=redirect-web-to-websecure@internal",
      ]

      connect {
        native = true
      }

      check {
        name     = "alive"
        type     = "http"
        path     = "/health"
        interval = "30s"
        timeout  = "5s"
      }      
    }    

    service {
      name = "opapibus"
      provider = "consul"
      task = "opapi"
      port = 11223

      connect {
        native = true
      }
    }      

    service {
      name = "opsyncbus"
      provider = "consul"
      task = "opsync"      
      port = 11224

      connect {
        native = true
      }
    }

    task "opapi" {
      driver = "podman"
      user = "2000"

      config {
        image = "1password/connect-api:latest"
        ports = ["opapi","opapibus"]
        userns = "keep-id"
        logging {
          driver = "journald"
          options = [
            {
            "tag" = "opapi"
            }
          ]
        }
      }

      env {
        OP_BUS_PEERS = "host.containers.internal:11224"
        OP_HTTP_PORT = "8080"
        OP_BUS_PORT = "11223"
        XDG_DATA_HOME = "alloc/data/"
      }

      resources {
          memory = 128
      }

      template {
        destination = "${NOMAD_SECRETS_DIR}/env"
        perms = "644"
        env = true
        data = <<EOT
{{ with nomadVar "nomad/jobs/op-connect" -}}
{{- $opConfig := printf "%s" .op_config -}}
OP_SESSION={{ $opConfig | base64Encode  }}
OP_CONNECT_TOKEN={{ .op_token }}
{{- end -}}
EOT
      }      
    }

    task "opsync" {
      driver = "podman"
      user = "2000"

      config {
        image = "1password/connect-sync:latest"
        ports = ["opsync","opsyncbus"]
        userns = "keep-id"  
        logging {
          driver = "journald"
          options = [
            {
            "tag" = "opsync"
            }
          ]
        }
      }

      env {
        OP_HTTP_PORT = "8081"
        OP_BUS_PEERS = "host.containers.internal:11223"
        OP_BUS_PORT = "11224"
        XDG_DATA_HOME = "alloc/data/"       
      }

      resources {
        memory = 128
      }

      template {
        destination = "${NOMAD_SECRETS_DIR}/env"
        perms = "644"
        env  = true
        data = <<EOT
{{ with nomadVar "nomad/jobs/op-connect" -}}
{{- $opConfig := printf "%s" .op_config -}}
OP_SESSION={{ $opConfig | base64Encode  }}
OP_CONNECT_TOKEN={{ .op_token }}
{{- end -}}
EOT
      }       
    }    
  }
}