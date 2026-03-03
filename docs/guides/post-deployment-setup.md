# Post-Deployment Setup Guide

All services are accessible at `https://{service}.octant.local`.

## 1. Grafana Setup

**URL:** https://grafana.octant.local

**First login:** Default credentials are `admin`/`admin` - you'll be prompted to change the password on first login. (Note: `GF_AUTH_BASIC_ENABLED=false` is set, so you may need to check whether anonymous access is intended or if this should be changed.)

**Datasources are already provisioned** via `grafana-datasources.yml`:
- Prometheus (default) at `prometheus.service.consul:9091`
- Loki at `loki.service.consul:3100`
- Tempo at `tempo.service.consul:3200` (with traces-to-logs and traces-to-metrics linking)

### Recommended Dashboards to Import

| Dashboard | ID | Purpose |
|---|---|---|
| Node Exporter Full | `1860` | Host CPU, memory, disk, network (uses node-exporter metrics) |
| Nomad Cluster | `12787` | Nomad job/allocation health |
| Consul Server | `13396` | Consul cluster health |
| Traefik | `17346` | Traefik request rates, errors, latencies |
| Loki & Promtail | `13639` | Log ingestion rates and errors |
| Alertmanager | `9578` | Alert routing and silencing overview |

**To import:** Dashboards > New > Import > paste the ID > select "Prometheus" as the datasource > Import.

The Node Exporter Full dashboard (1860) is the highest priority - it gives immediate visibility into the host metrics the node-exporter and podman-exporter roles are collecting.

## 2. Uptime Kuma Setup

**URL:** https://uptimekuma.octant.local

**First visit:** You'll be prompted to create an admin account (username + password). This is a one-time setup stored in `/mnt/services/uptimekuma/data`.

### Recommended Monitors

External (HTTPS through Traefik - validates the full path):

| Name | Type | URL | Interval |
|---|---|---|---|
| Grafana | HTTP(s) | `https://grafana.octant.local` | 60s |
| Prometheus | HTTP(s) | `https://prometheus.octant.local/-/healthy` | 60s |
| Nomad | HTTP(s) | `https://nomad.octant.local` | 60s |
| Consul | HTTP(s) | `https://consul.octant.local` | 60s |
| Traefik | HTTP(s) | `https://traefik.octant.local` | 60s |

Internal (via Consul DNS - validates service health without Traefik):

| Name | Type | URL | Interval |
|---|---|---|---|
| Loki | HTTP(s) | `http://loki.service.consul:3100/ready` | 60s |
| Tempo | HTTP(s) | `http://tempo.service.consul:3200/ready` | 60s |
| Alertmanager | HTTP(s) | `http://alertmanager.service.consul:9093/-/healthy` | 60s |

Uptime Kuma complements Gatus - Gatus does internal health checks (already configured for 11 endpoints), while Uptime Kuma can monitor external accessibility and provide a public-facing status page.

**Optional:** Set up notifications (Settings > Notifications) - Uptime Kuma supports Slack, Discord, email, Telegram, ntfy, and many more.

## 3. Alertmanager - Configure a Notification Receiver

Currently the `default` receiver has no notification targets. To get alerts delivered, edit `terraform/alertmanager/alertmanager.yml` and add a receiver (e.g., ntfy):

```yaml
receivers:
  - name: default
    webhook_configs:
      - url: 'https://ntfy.octant.local/octant-alerts'
```

Then apply:

```bash
cd terraform/alertmanager && terraform apply
```

## 4. Verify Gatus

**URL:** https://gatus.octant.local

Already configured to monitor 11 endpoints across three groups:
- **monitoring:** Grafana, Prometheus, Loki, Tempo, Alertmanager, Alloy
- **infrastructure:** Traefik, Consul, Nomad
- **apps:** Uptime Kuma, Phoenix

Check that all endpoints show green.

## 5. Verify Prometheus Targets

**URL:** https://prometheus.octant.local/targets

The `consul-metrics` catch-all job should show targets for:
- 3x node-exporter (port 9100)
- 3x podman-exporter-rootless (port 9883)
- 3x podman-exporter-rootful (port 9882)
- 1x traefik-metrics (port 8082)

All should show state UP.

## 6. Traefik Dashboard

**URL:** https://traefik.octant.local (port 9002 via HAProxy)

Useful for verifying all routers and services are properly registered.

## Service Reference

| Service | Internal URL | External URL | Port |
|---|---|---|---|
| Prometheus | `prometheus.service.consul:9091` | `https://prometheus.octant.local` | 9091 |
| Grafana | `grafana.service.consul:3000` | `https://grafana.octant.local` | 3000 |
| Loki | `loki.service.consul:3100` | `https://loki.octant.local` | 3100 |
| Tempo | `tempo.service.consul:3200` | `https://tempo.octant.local` | 3200 |
| Alertmanager | `alertmanager.service.consul:9093` | `https://alertmanager.octant.local` | 9093 |
| Alloy | `alloy.service.consul:12345` | (not exposed) | 12345 |
| Gatus | `gatus.service.consul:8080` | `https://gatus.octant.local` | 8080 |
| Uptime Kuma | `uptimekuma.service.consul:3001` | `https://uptimekuma.octant.local` | 3001 |
| Traefik | `traefik.service.consul` | `https://traefik.octant.local` | 80/443/8082/9002 |
