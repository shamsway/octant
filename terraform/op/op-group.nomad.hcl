variable "datacenter" {
  type = string
  default = "octant"
}

variable "domain" {
  type = string
  default = "octant.net"
}

variable "certresolver" {
  type = string
  default = "cloudflare"
}

variable "servicename" {
  type = string
  default = "op-connect"
}

variable "dns" {
  type = list(string)
  default = ["192.168.1.1", "192.168.1.6", "192.168.1.7"]
}

variable "opapi_image" {
  type = string
  default = "1password/connect-api:latest"
}

variable "osync_image" {
  type = string
  default = "1password/connect-sync:latest"
}

job "op-connect" {
  datacenters = ["${var.datacenter}"]
  type = "service"

  constraint {
      attribute = "${meta.rootless}"
      value     = "true"
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
        servers = var.dns
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
        "traefik.http.routers.${var.servicename}.rule=Host(`opapi.${var.domain}`)",
        "traefik.http.routers.${var.servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${var.servicename}.tls.certresolver=${var.certresolver}",
        "traefik.http.routers.${var.servicename}.middlewares=redirect-web-to-websecure@internal",
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
        "traefik.http.routers.${var.servicename}.rule=Host(`opsync.${var.domain}`)",
        "traefik.http.routers.${var.servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${var.servicename}.tls.certresolver=${var.certresolver}",
        "traefik.http.routers.${var.servicename}.middlewares=redirect-web-to-websecure@internal",
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
        image = var.opapi_image
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
        image = "var.opsync_image"
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