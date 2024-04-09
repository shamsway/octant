job "grafana-agent" {
  region      = "home"
  datacenters = ["shamsway"]
  type        = "system"

  group "monitoring" {

    task "grafana-agent" {
      driver = "podman"
      config {
        image = "docker.io/grafana/agent:v0.40.3"
        args = [
          "-config.file",
          "local/local-config.yaml",
        ]
        volumes = [
          "/var/log/journal:/var/log/journal"
        ]        
      }

      service {
        name = "grafana-agent"  
      }

      template {
        data = <<EOH
server:
  log_level: info

logs:
  configs:
  - name: default
    positions:
      filename: /tmp/positions.yaml
    scrape_configs:
      - job_name: journal
        journal:
          max_age: 12h
          path: /var/log/journal
          labels:
            job: journal
        relabel_configs:
          - source_labels: ['__journal__systemd_unit']
            target_label: 'unit'
          - source_labels: ['__journal_container_name']
            target_label: 'container'

    clients:
      - url: http://loki.shamsway.net:3100/loki/api/v1/push
EOH
        destination = "local/local-config.yaml"
      }
    }
  }
}