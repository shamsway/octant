job "op-connect" {
  datacenters = ["shamsway"]
  type = "service"

  constraint {
      attribute = "${meta.rootless}"
      value     = "true"
  }

  group "opapi" {
    volume "1password-data" {
      type      = "host"
      read_only = false
      source    = "1password-data"
    }

    network {
      port "opapi" {
        to = 8080
      }

      port "opapibus" {
        static = 11223
        to = 11223
      }

      dns {
        servers = ["192.168.252.1"]
      }
    }

    service {
      name = "opapi"
      provider = "consul"
      port = "opapi"
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
        interval = "60s"
        timeout  = "5s"
      }
    }

    service {
      name = "opapibus"
      provider = "consul"
      port = 11223

      connect {
        native = true
      }

      check {
        name     = "alive"
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
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
        OP_CONNECT_TOKEN = "eyJhbGciOiJFUzI1NiIsImtpZCI6ImZsaWNuZ3llc3ZjZmRwc3RwcWlibnVscGZlIiwidHlwIjoiSldUIn0.eyIxcGFzc3dvcmQuY29tL2F1dWlkIjoiRzNMVkFaU1dQSkFSWEZWNVhGTkFVVjZMQTQiLCIxcGFzc3dvcmQuY29tL3Rva2VuIjoiaF8tWGFaYkoyaHFtZ1gxS1g2cVlZU3ByckFSZDZKeHoiLCIxcGFzc3dvcmQuY29tL2Z0cyI6WyJ2YXVsdGFjY2VzcyJdLCIxcGFzc3dvcmQuY29tL3Z0cyI6W3sidSI6Im5hc3djc2dxdzR6emtsdWo2emJkM3IycWZxIiwiYSI6NDh9XSwiYXVkIjpbImNvbS4xcGFzc3dvcmQuY29ubmVjdCJdLCJzdWIiOiJQUDMzVFZZQ0hWR0gzSDQyUFdQUkFDQUNPVSIsImlhdCI6MTcxNDY2NzAyNSwiaXNzIjoiY29tLjFwYXNzd29yZC5iNSIsImp0aSI6InNqY3Bxa2FpdWNtY3l3c3Nqd3o1dmRwZmptIn0.0T6uCD_WQ63rquWTWb4CGiA8o05n2Frx8yQRVHsOj8oMc_Ui8talWc4B-J0rNO3Jzp_q53SsUpQYjLffSOr34A"
        OP_BUS_PEERS = "opsync.service.consul:11224"
        OP_HTTP_PORT = "8080"
        OP_BUS_PORT = "11223"
        XDG_DATA_HOME = "/data/"
      }

      resources {
          memory = 128
      }

      volume_mount {
        volume      = "1password-data"
        destination = "/data/"
        read_only   = false
      }

      template {
        destination = "${NOMAD_SECRETS_DIR}/1password-credentials.json"
        perms = "644"
        env = true
        data = <<EOT
FOO="{{ range nomadService "opsyncbus" }}{{ .Address }}:{{ .Port }}{{ end }}"        
{{ with nomadVar "nomad/jobs/op-connect" -}}
OP_SESSION={{ (printf "%s" .op_config) | base64Encode }}
{{- end -}}
EOT
      }      
    }
  }

  group "opsync" {
    volume "1password-data" {
      type      = "host"
      read_only = false
      source    = "1password-data"
    }

    network {
      port "opsync" {
        to = 8081
      }

      port "opsyncbus" {
        static = 11224
        to = 11224    
      }
      
      dns {
        servers = ["192.168.252.1"]
      }      
    }

    service {
      name = "opsync"
      provider = "consul"
      port = "opsync"
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
        interval = "60s"
        timeout  = "5s"
      }      
    }

    service {
      name = "opsyncbus"
      provider = "consul"
      port = 11224

      connect {
        native = true
      }

      check {
        name     = "alive"
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
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
        OP_CONNECT_TOKEN = "eyJhbGciOiJFUzI1NiIsImtpZCI6ImZsaWNuZ3llc3ZjZmRwc3RwcWlibnVscGZlIiwidHlwIjoiSldUIn0.eyIxcGFzc3dvcmQuY29tL2F1dWlkIjoiRzNMVkFaU1dQSkFSWEZWNVhGTkFVVjZMQTQiLCIxcGFzc3dvcmQuY29tL3Rva2VuIjoiaF8tWGFaYkoyaHFtZ1gxS1g2cVlZU3ByckFSZDZKeHoiLCIxcGFzc3dvcmQuY29tL2Z0cyI6WyJ2YXVsdGFjY2VzcyJdLCIxcGFzc3dvcmQuY29tL3Z0cyI6W3sidSI6Im5hc3djc2dxdzR6emtsdWo2emJkM3IycWZxIiwiYSI6NDh9XSwiYXVkIjpbImNvbS4xcGFzc3dvcmQuY29ubmVjdCJdLCJzdWIiOiJQUDMzVFZZQ0hWR0gzSDQyUFdQUkFDQUNPVSIsImlhdCI6MTcxNDY2NzAyNSwiaXNzIjoiY29tLjFwYXNzd29yZC5iNSIsImp0aSI6InNqY3Bxa2FpdWNtY3l3c3Nqd3o1dmRwZmptIn0.0T6uCD_WQ63rquWTWb4CGiA8o05n2Frx8yQRVHsOj8oMc_Ui8talWc4B-J0rNO3Jzp_q53SsUpQYjLffSOr34A"
        OP_HTTP_PORT = "8081"
        OP_BUS_PEERS = "opapi.service.consul:11223"
        OP_BUS_PORT = "11224"
        XDG_DATA_HOME = "/data/"        
      }

      resources {
        memory = 128
      }

      volume_mount {
        volume      = "1password-data"
        destination = "/data/"
        read_only   = false
      }

      template {
        destination = "${NOMAD_SECRETS_DIR}/1password-credentials.json"
        perms = "644"
        env  = true
        data = <<EOT
FOO="{{ range nomadService "opapibus" }}{{ .Address }}:{{ .Port }}{{ end }}"      
{{ with nomadVar "nomad/jobs/op-connect" -}}
OP_SESSION={{ (printf "%s" .op_config) | base64Encode }}
{{- end -}}
EOT
      }       
    }    
  }
}