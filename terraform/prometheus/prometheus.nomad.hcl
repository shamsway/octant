job "prometheus" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "false"
  }

  constraint {
    attribute = "$${node.unique.name}"
    value     = "${node_name}"
  }

  group "prometheus" {
    volume "prometheus-data" {
      type            = "csi"
      source          = "prometheus-data"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    network {
      port "http" {
        static = 9091
        to     = 9091
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      task     = "prometheus"
      port     = "http"
      provider = "consul"

      connect {
        native = true
      }

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${servicename}.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}.tls.certresolver=${certresolver}",
        "traefik.http.routers.${servicename}.middlewares=redirect-web-to-websecure@internal",
        "homepage.group=Monitoring",
        "homepage.name=Prometheus",
        "homepage.icon=prometheus",
        "homepage.description=Metrics",
      ]

      check {
        type     = "http"
        path     = "/-/healthy"
        name     = "http"
        interval = "30s"
        timeout  = "5s"
      }

      check_restart {
        limit           = 3
        grace           = "60s"
        ignore_warnings = false
      }
    }

    task "volume-init" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      volume_mount {
        volume      = "prometheus-data"
        destination = "/opt/prometheus"
      }

      config {
        image      = "busybox:latest"
        command    = "/bin/sh"
        args       = ["-c", "chown -R 65534:65534 /opt/prometheus"]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }

    task "prometheus" {
      driver = "docker"
      user   = "65534:65534"

      volume_mount {
        volume      = "prometheus-data"
        destination = "/opt/prometheus"
      }

      config {
        image = "${image}"
        args = [
          "--storage.tsdb.path", "/opt/prometheus",
          "--web.listen-address", "0.0.0.0:9091",
          "--storage.tsdb.retention.time", "45d",
          "--web.enable-remote-write-receiver",
        ]
        ports = ["http"]
        volumes = [
          "local/alerts.yml:/prometheus/alerts.yml",
          "local/prometheus.yml:/prometheus/prometheus.yml",
        ]

        logging {
          type = "journald"
          config {
            tag = "${servicename}"
          }
        }
      }

      # main configuration file
      template {
        data = <<EOH
global:
  scrape_interval:     15s
  evaluation_interval: 60s
  external_labels:
    cluster: octant
    environment: home

alerting:
  alertmanagers:
    - consul_sd_configs:
        - server: 'consul.service.consul:8500'
          services: ['alertmanager']
          scheme: http

rule_files:
  - "alerts.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['127.0.0.1:9091']

  - job_name: 'hypervisor-host'
    static_configs:
      - targets: ['192.168.122.1:9100']

  - job_name: 'and-gpu-metrics'
    static_configs:
      - targets: ['192.168.122.1:5050']

  - job_name: 'traefik'
    metrics_path: /metrics
    static_configs:
      - targets: {{ range service "traefik-metrics" -}}['traefik.service.consul:{{ .Port }}']{{- end }}

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

  - job_name: 'alloy'
    consul_sd_configs:
      - server: 'consul.service.consul:8500'
        services: ['alloy']
        scheme: http
    metrics_path: /metrics
    relabel_configs:
      - source_labels: ['__meta_consul_node']
        target_label: host

  - job_name: 'tempo'
    consul_sd_configs:
      - server: 'consul.service.consul:8500'
        services: ['tempo']
        scheme: http
    metrics_path: /metrics
    relabel_configs:
      - source_labels: ['__meta_consul_node']
        target_label: host

  - job_name: 'alertmanager'
    consul_sd_configs:
      - server: 'consul.service.consul:8500'
        services: ['alertmanager']
        scheme: http
    metrics_path: /metrics
    relabel_configs:
      - source_labels: ['__meta_consul_node']
        target_label: host

  - job_name: 'consul-metrics'
    consul_sd_configs:
      - server: 'consul.service.consul:8500'
        tags: ['metrics']
        scheme: http
    relabel_configs:
      - source_labels: ['__meta_consul_service']
        target_label: job
      - source_labels: ['__meta_consul_node']
        target_label: host
      - source_labels: ['__meta_consul_tags']
        target_label: consul_tags
EOH

        destination   = "local/prometheus.yml"
        change_mode   = "signal"
        change_signal = "SIGHUP"
        env           = false
      }

      template {
        change_mode     = "noop"
        destination     = "local/alerts.yml"
        left_delimiter  = "[["
        right_delimiter = "]]"
        data            = <<EOH
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

  - alert: InstanceDown
    expr: up == 0
    for: 5m
    labels:
      severity: page
    annotations:
      summary: "Instance {{ $labels.instance }} down"
      description: "{{ $labels.instance }} of job {{ $labels.job }} has been down for more than 5 minutes."

  - alert: DiskUsage
    expr: (1 - node_filesystem_avail_bytes{fstype!~"tmpfs|fuse.lxcfs|squashfs"} / node_filesystem_size_bytes) * 100 > 80
    for: 5m
    labels:
      severity: page
    annotations:
      summary: "Host {{ $labels.instance }} disk {{ $labels.mountpoint }} usage alert"
      description: "{{ $labels.instance }} filesystem {{ $labels.mountpoint }} is over 80% full."

  - alert: NodeExporterDown
    expr: absent(up{job="node-exporter"} == 1)
    for: 5m
    labels:
      severity: page
    annotations:
      summary: "Node exporter missing"
      description: "No node-exporter targets are reachable. Host metrics unavailable."

  - alert: LokiDown
    expr: absent(up{job="loki"} == 1)
    for: 5m
    labels:
      severity: page
    annotations:
      summary: "Loki is down"
      description: "No Loki targets are reachable. Log ingestion and querying unavailable."

  - alert: TempoDown
    expr: absent(up{job="tempo"} == 1)
    for: 5m
    labels:
      severity: page
    annotations:
      summary: "Tempo is down"
      description: "No Tempo targets are reachable. Trace ingestion and querying unavailable."

  - alert: AlertmanagerDown
    expr: absent(up{job="alertmanager"} == 1)
    for: 5m
    labels:
      severity: page
    annotations:
      summary: "Alertmanager is down"
      description: "No Alertmanager targets are reachable. Alert routing unavailable."

  - alert: AlloyDown
    expr: absent(up{job="alloy"} == 1)
    for: 5m
    labels:
      severity: page
    annotations:
      summary: "Alloy is down"
      description: "No Alloy targets are reachable. Log and metric collection may be interrupted."

  - alert: HighMemoryPressure
    expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 90
    for: 5m
    labels:
      severity: page
    annotations:
      summary: "High memory pressure on {{ $labels.instance }}"
      description: "{{ $labels.instance }} is using more than 90% of RAM ({{ $value | printf \"%.0f\" }}% used)."

  - alert: HighCpuUsage
    expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 90
    for: 10m
    labels:
      severity: page
    annotations:
      summary: "High CPU usage on {{ $labels.instance }}"
      description: "{{ $labels.instance }} CPU usage has been above 90% for more than 10 minutes ({{ $value | printf \"%.0f\" }}% used)."

  - alert: CephHealthWarn
    expr: ceph_health_status != 0
    for: 5m
    labels:
      severity: page
    annotations:
      summary: "Ceph cluster health degraded"
      description: "Ceph cluster health status is {{ $value }} (0=OK, 1=WARN, 2=ERR) for more than 5 minutes."

  - alert: CephExporterDown
    expr: absent(up{job="ceph-exporter"} == 1)
    for: 5m
    labels:
      severity: page
    annotations:
      summary: "Ceph exporter is down"
      description: "No ceph-exporter targets are reachable. Ceph storage metrics unavailable."
EOH
      }

      resources {
        cpu    = 100
        memory = 512
      }
    }
  }
}
