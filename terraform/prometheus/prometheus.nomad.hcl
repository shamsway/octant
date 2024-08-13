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
  default = "prometheus"
}

variable "dns" {
  type = list(string)
  default = ["192.168.1.1", "192.168.1.6", "192.168.1.7"]
}

variable "image" {
  type = string
  default = "docker.io/prom/prometheus:v2.51.1"
}

job "prometheus" {
  region      = "home"
  datacenters = ["${var.datacenter}"]
  type        = "service"

  constraint {
    attribute = "${meta.rootless}"
    value = "true"
  }

  affinity {
    attribute = "${meta.class}"
    value     = "physical"
    weight    = 100
  }

  group "prometheus" {
    network {
      port "http" {
        static = "9091"
      }

      dns {
        servers = var.dns
      }      
    }

    volume "prometheus-data" {
      type      = "host"
      read_only = false
      source    = "prometheus-data"
    }


    service {
      name = var.servicename
      port = "http"
      provider = "consul"
      connect {
        native = true
      }

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${var.servicename}.rule=Host(`${var.servicename}.${var.domain}`)",
        "traefik.http.routers.${var.servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${var.servicename}.tls.certresolver=${var.certresolver}",
        "traefik.http.routers.${var.servicename}.middlewares=redirect-web-to-websecure@internal",     
      ]

      check {
        type     = "http"
        path     = "/-/healthy"
        name     = "http"
        interval = "5s"
        timeout  = "2s"
      }
    }

    task "prometheus" {
      driver = "podman"
      user = "2000:100"

      volume_mount {
        volume      = "prometheus-data"
        destination = "/opt/prometheus"
        read_only   = false
      }

      config {
        image = var.image
        userns = "keep-id"
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "${var.servicename}"
            }
          ]
        } 
        args = ["--storage.tsdb.path", "/opt/prometheus", "--web.listen-address", "0.0.0.0:9091", "--storage.tsdb.retention.time", "365d"]
        ports = ["http"]
        volumes = [
          "local/alerts.yml:/prometheus/alerts.yml",
          "local/prometheus.yml:/prometheus/prometheus.yml",
        ]
      }

      # main configuration file
      template {
        data = <<EOH
global:
  scrape_interval:     15s # Set the scrape interval to every 15 seconds. Default is every 1 minute.
  evaluation_interval: 60s # Evaluate rules every 15 seconds. The default is every 1 minute.
  # scrape_timeout is set to the global default (10s).

# Load rules once and periodically evaluate them according to the global 'evaluation_interval'.
rule_files:
  - "alerts.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['127.0.0.1:9091']

  - job_name: 'traefik'
    metrics_path: /metrics
    static_configs:
      - targets: {{ range service "traefik-metrics" -}}['traefik.service.consul:{{ .Port }}']{{- end }}

  # - job_name: 'nomad-jobs'
  #   metrics_path: /metrics
  #   consul_sd_configs:
  #     - server: 'consul.shamsway.net:8500'
  #       tags: ['metrics']
  #       scheme: http
  #   relabel_configs:
  #     - source_labels: ['__meta_consul_dc']
  #       target_label: 'dc'
  #     - source_labels: ['__meta_consul_service']
  #       target_label: 'job'
  #     - source_labels: ['__meta_consul_node']
  #       target_label: 'host'
  #     - source_labels: ['__meta_consul_tags']
  #       target_label: 'tags'
  #     - source_labels: ['__meta_consul_tags']
  #       regex: '.*job-(.+?)(,.*)?'
  #       replacement: '${1}'
  #       target_label: 'job_name'
  #     - source_labels: ['__meta_consul_address']
  #       target_label: '__address__'
  #       replacement: '${1}:'
  #     - source_labels: ['__address__', '__meta_consul_service_port']
  #       target_label: '__address__'
  #       regex: '(.+)(?::\d+);(\d+)'
  #       replacement: '${1}:${2}'

  - job_name: 'consul'
    metrics_path: /v1/agent/metrics
    honor_labels: true
    params:
      format: ['prometheus']
    consul_sd_configs:
      - server: 'consul.service.consul:8500'
        services: ['consul']
        scheme: http
    relabel_configs:
      - source_labels: ['__meta_consul_dc']
        target_label:  'dc'
      - source_labels: ['__meta_consul_node']
        target_label:  'host'
      - source_labels: ['__meta_consul_tags']
        target_label: 'tags'
      - source_labels: [__address__]
        action: replace
        regex: ([^:]+):.*
        replacement: $1:8500
        target_label: __address__

  - job_name: 'nomad'
    consul_sd_configs:
    - server: 'consul.service.consul:8500'
      services: ['nomad']
      tags: ['http']
      scheme: http
    scrape_interval: 10s
    metrics_path: /v1/metrics
    params:
      format: ['prometheus']
    relabel_configs:
      - source_labels: ['__meta_consul_dc']
        target_label:  'dc'
      - source_labels: [__meta_consul_service]
        target_label:  'job'
      - source_labels: ['__meta_consul_node']
        target_label:  'host'

  - job_name: 'nomad-client'
    consul_sd_configs:
    - server: 'consul.service.consul:8500'
      services: ['nomad-client']
      tags: ['http']
      scheme: http
    scrape_interval: 10s
    metrics_path: /v1/metrics
    params:
      format: ['prometheus']
    relabel_configs:
      - source_labels: ['__meta_consul_dc']
        target_label:  'dc'
      - source_labels: [__meta_consul_service]
        target_label:  'job'
      - source_labels: ['__meta_consul_node']
        target_label:  'host'
EOH

        destination   = "local/prometheus.yml"
        change_mode   = "signal"
        change_signal = "SIGHUP"
        env           = false
      }

      template {
        change_mode = "noop"
        destination = "local/alerts.yml"
        left_delimiter = "[["
        right_delimiter = "]]"
        data = <<EOH
---
groups:
- name: prometheus_alerts
  rules:
  - alert: Traefik Down
    expr: absent(nomad_client_allocs_cpu_user{task="traefik"})
    for: 2m
    labels:
      severity: page
    annotations:
      description: "Traefik is down."
  # Alert for any instance that is unreachable for >5 minutes.
  - alert: InstanceDown
    expr: up == 0
    for: 5m
    labels:
      severity: page
    annotations:
      summary: "Instance {{ $labels.instance }} down"
      description: "{{ $labels.instance }} of job {{ $labels.job }} has been down for more than 5 minutes."
  # Alert for any device that is over 80% capacity  
  - alert: DiskUsage
    expr: avg(disk_used_percent) by (host, device) > 80
    for: 5m
    labels:
      severity: page
    annotations:
      summary: "Host {{ $labels.host }} disk {{ $labels.device }} usage alert"
      description: "{{ $labels.host }} is using over 80% of its device: {{ $labels.device }}"

EOH
      }

      resources {
        cpu    = 100
        memory = 256
      }
    }
  }
}