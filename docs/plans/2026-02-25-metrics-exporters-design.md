# Metrics Exporters & Prometheus Auto-Discovery Design

**Date:** 2026-02-25
**Branch:** `feature/app-migration`

## Goal

Port node-exporter and podman-exporter Ansible roles from octant-private, and add a Consul SD catch-all scrape job to Prometheus so future metrics-tagged services are discovered automatically.

## Components

### 1. Ansible Role: node-exporter

Ported from `octant-private/roles/node-exporter/`. Installs the Prometheus node exporter on all cluster nodes via apt and registers it with Consul for service discovery.

- Install `prometheus-node-exporter` package
- Start and enable the systemd service
- Register with Consul agent on port 9100, tagged `"metrics"`
- Reload consul-agent on definition change

Added to `octant.yml` after `restic`:
```yaml
- role: node-exporter
  tags: node-exporter
```

### 2. Ansible Role: podman-exporter

Ported from `octant-private/roles/podman-exporter/`. Runs Prometheus podman exporter containers to expose container metrics for both rootless and rootful Podman instances.

- **Rootless:** systemd unit on port 9883, registered with consul-agent, tagged `["metrics", "podman", "rootless"]`
- **Rootful:** systemd unit on port 9882, registered with consul-agent-root, tagged `["metrics", "podman", "rootful"]`
- Conditional enable/disable for both modes
- Container image: `quay.io/navidys/prometheus-podman-exporter:v1.20.0`

Added to `octant.yml` after `node-exporter`:
```yaml
- role: podman-exporter
  tags: podman-exporter
  when: podman == true
```

### 3. Prometheus Catch-All Scrape Job

Replace the four individual scrape jobs (`node-exporter`, `podman-exporter`, `podman-exporter-rootless`, `podman-exporter-rootful`) with a single Consul SD catch-all:

```yaml
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
```

This discovers any Consul service tagged `"metrics"` and sets the `job` label to the service name. Explicit scrape jobs for consul, nomad, alloy, tempo, and alertmanager remain unchanged since they use custom metrics paths or parameters.

### 4. Consul Tag Convention

Services opt into Prometheus scraping by adding `"metrics"` to their Consul service tags. Services already using this tag:
- `traefik-metrics` (existing, uses separate static config)
- `podman-exporter-rootless` (from octant-private)
- `podman-exporter-rootful` (from octant-private)

New addition:
- `node-exporter` (adding `"metrics"` tag, not present in octant-private)

## Adaptations from octant-private

The octant-private roles use `configdirs['consul-agent']` and `configdirs['consul-agent-root']` variables which resolve to `/opt/homelab/config/...` in octant-private but `/opt/octant/config/...` in this repo. Since both repos reference the variable (not hardcoded paths), no path changes are needed.

The node-exporter Consul registration in octant-private lacks the `"metrics"` tag. We add it here to work with the catch-all scrape job.

## What Stays Unchanged

- Prometheus alert rules (already reference node-exporter metrics)
- Explicit scrape jobs for consul, nomad, nomad-client, alloy, tempo, alertmanager (custom metrics paths)
- Traefik metrics scrape (uses Consul template range, not Consul SD)
- Prometheus self-scrape (static config)
