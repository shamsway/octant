job "ingress-lb" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type = "system"

  constraint {
    attribute = "$${meta.rootless}"
    value = "false"
  }

  group "ingress-lb" {
    network {
      port "http" {
        static = "80"
        to = "80"
      }
      port "https" {
        static = "443"
        to = "443"
      }
      port "httpalt" {
        static = "8081"
        to = "8081"
      }      
      dns {
        servers = ${dns}
      }
    }

    update {
      max_parallel     = 1
      min_healthy_time = "30s"
      auto_revert      = true
    }

    task "nginx" {
      driver = "podman"
      config {
        image = "${image}"
        network_mode = "bridge"
        ports = ["http", "https", "httpalt"]
        volumes = ["local:/etc/nginx"]
      }

      template {
        data = <<EOF
pid /tmp/nginx.pid;        
events {}
stream {
  upstream traefik {
    least_conn;
    {{- range service "traefik" }}
    server {{ .Address }}:{{ .Port }};{{- end }}
  }

  upstream traefik-http {
    least_conn;
    {{- range service "traefik-http" }}
    server {{ .Address }}:{{ .Port }};{{- end }}
  }  

  server {
    listen 443;
    proxy_pass traefik;
  }

  server {
    listen 80;
    proxy_pass traefik-http;
  }
}

http {
  upstream consul {
    least_conn;
    {{- range service "consul" }}
    server {{ .Address }}:8500;{{- end }}
  }  

  upstream nomad {
    least_conn;
    {{- range service "http.nomad" }}
    server {{ .Address }}:{{ .Port }};{{- end }}
  }

  server {
    listen 8081;
    server_name consul.${domain};
    location / {
      proxy_pass http://consul;
      proxy_buffering off;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-Host $host;
      proxy_set_header X-Forwarded-Port $server_port;
    }
  }

  server {
    listen 8081;
    server_name nomad.${domain};
    location / {
      proxy_pass http://nomad;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-Host $host;
      proxy_set_header X-Forwarded-Port $server_port;      
    }
  }
}
EOF
        destination   = "local/nginx.conf"
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }
      
      resources {
        cpu    = 100
        memory = 128
      }      
    }    
  }
}