job "prometheus" {
  region      = "home"
  datacenters = ["shamsway"]
  type        = "service"

  constraint {
    attribute = "${node.unique.name}"
    operator  = "regexp"
    value     = "^.*[^-][^r][^o][^o][^t]$"
  } 

  group "monitoring" {
    count = 1

    network {
      port "http" {
        static = "9091"
      }
    }

    volume "prometheus-data" {
      type      = "host"
      read_only = false
      source    = "prometheus-data"
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
        image = "docker.io/prom/prometheus:v2.51.1"
        userns = "keep-id"
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "prometheus"
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

      service {
        name = "prometheus"
        port = "http"
        provider = "consul"
        tags = [
            "traefik.enable=true",
            "traefik.http.routers.prometheus.rule=Host(`prometheus.shamsway.net`)",
            "traefik.http.routers.prometheus.entrypoints=web,websecure",
            "traefik.http.routers.prometheus.tls.certresolver=cloudflare",
            "traefik.http.routers.prometheus.middlewares=redirect-web-to-websecure@internal",       
        ]

        check {
          type     = "http"
          path     = "/-/healthy"
          name     = "http"
          interval = "5s"
          timeout  = "2s"
        }
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

  - job_name: 'ceph'
    honor_labels: true
    static_configs:
      - targets: ['jerry.shamsway.net:9283']
        labels:
          instance: jerry.shamsway.net
          alias: ceph-exporter

  - job_name: 'traefik'
    metrics_path: /metrics
    static_configs:
      - targets: ['traefik.shamsway.net:8082']

  - job_name: 'nomad-jobs'
    metrics_path: /metrics
    consul_sd_configs:
      - server: 'consul.shamsway.net:8500'
        tags: ['metrics']
        scheme: http
    relabel_configs:
      - source_labels: ['__meta_consul_dc']
        target_label:  'dc'
      - source_labels: [__meta_consul_service]
        target_label:  'job'
      - source_labels: ['__meta_consul_node']
        target_label:  'host'
      - source_labels: ['__meta_consul_tags']
        target_label: 'tags'
      - source_labels: ['__meta_consul_tags']
        regex: '.*job-(.*?)(,.*)'
        replacement: '${1}'
        target_label: 'job_name'

  - job_name: 'consul-server'
    metrics_path: /v1/agent/metrics
    honor_labels: true
    params:
      format: ['prometheus']
    consul_sd_configs:
      - server: '{{ env "NOMAD_IP_http" }}:8500'
        services: ['nomad-client']
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

  - job_name: 'nomad-client'
    consul_sd_configs:
    - server: '{{ env "NOMAD_IP_http" }}:8500'
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