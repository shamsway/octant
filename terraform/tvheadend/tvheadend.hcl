
job "tvheadend" {
  datacenters = ["shamsway"]
  type        = "service"

  constraint {
    attribute = "${meta.rootless}"
    value = "false"
  }

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }

  group "tvheadend" {
    count = 1

    affinity {
      attribute = "${node.unique.name}"
      value     = "bobby-root"
      weight    = 100
    }

    volume "tvheadend-config" {
      type      = "host"
      read_only = false
      source    = "tvheadend-config"
    }

    volume "tvheadend-recordings" {
      type      = "host"
      read_only = false
      source    = "tvheadend-recordings"
    }

    network {
      port "http" {
        static = 9981
      }
      port "http" {
        static = 9981
      }
      port "htsp-2" {
        static = 9982
      }
      port "htsp-3" {
        static = 9983
      }
      port "htsp-4" {
        static = 9984
      }
      port "htsp-5" {
        static = 9985
      }
      port "htsp-6" {
        static = 9986
      }
      port "htsp-7" {
        static = 9987
      }
      port "htsp-8" {
        static = 9988
      }
      mode = "bridge"                  
    }

    service {
      name = "tvheadend"
      port = "http"
      provider = "consul"

      connect {
        native = true
      }   

      check {
        type     = "http"
        path     = "/"
        interval = "60s"
        timeout  = "4s"
      }
    }

    task "tvheadend" {
      driver = "podman"      
      config {
        image = "docker.io/linuxserver/tvheadend"
        ports = ["http","htsp-2","htsp-3","htsp-4","htsp-5","htsp-6","htsp-7","htsp-8"]      
        privileged = true
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "tvheadend"
            }
          ]
        }          
      }

      env {
        PUID  = 2000
        PGID  = 2000
        TZ    = "America/New_York"
      }

      volume_mount {
        volume      = "tvheadend-config"
        destination = "/config"
        read_only   = false
      }

      volume_mount {
        volume      = "tvheadend-recordings"
        destination = "/recordings"
        read_only   = false
      }      
     }
    }
  }
  