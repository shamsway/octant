# Octant Lab Overview Dashboard — Design

**Date:** 2026-03-09
**Status:** Approved
**Delivery:** Provisioned JSON via Grafana provisioning in the Nomad job

## Overview

A single panoramic Grafana dashboard with collapsible row sections, designed for dual use: daily operational glance and polished demos/presentations. Auto-refreshes every 30s with a 1-hour default time range.

## Data Sources

All three configured Grafana data sources are used:

| Source | UID | URL | Role |
|--------|-----|-----|------|
| Prometheus | `prometheus` | `http://prometheus.service.consul:9091` | Metrics (default) |
| Loki | `loki` | `http://loki.service.consul:3100` | Logs |
| Tempo | `tempo` | `http://tempo.service.consul:3200` | Traces |

### Key Metric Families

- **Node/Host:** `node_*` from hypervisor node exporter (192.168.122.1:9100) and per-VM exporters
- **GPU:** `amd_gpu_*` from AMD Device Metrics Exporter (192.168.122.1:5050) — **8x MI300X OAMs**, ~192 GB VRAM each
- **Orchestration:** `nomad_*`, `consul_*` from Nomad/Consul servers and clients
- **Reverse Proxy:** Traefik metrics via Consul service discovery
- **Observability:** `loki_*`, `tempo_*`, `ALERTS` from the LGTM stack
- **Health:** Gatus endpoint metrics (if scraped)

### GPU Metric Details

All `amd_gpu_*` metrics include labels: `gpu_id`, `card_series`, `card_vendor`, `driver_version`, `vbios_version`, `serial_number`, `gpu_uuid`, `cluster_name`.

Key metrics:
- `amd_gpu_gfx_activity` — Graphics engine utilization (0-100%)
- `amd_gpu_used_vram` / `amd_gpu_total_vram` — VRAM in MB
- `amd_gpu_junction_temperature` — Hot-spot temperature (°C)
- `amd_gpu_memory_temperature` — HBM memory temperature (°C)
- `amd_gpu_power_usage` / `amd_gpu_package_power` — Power draw (W)
- `amd_gpu_health` — Health status (0 = unhealthy, 1 = healthy)
- `amd_gpu_nodes_total` — GPU count (8)
- `amd_gpu_clock` — Clock frequency (MHz)
- `amd_gpu_ecc_*` — ECC error counts
- `amd_gpu_free_vram` / `amd_gpu_free_gtt` — Free memory

## Dashboard Layout

### Row 0: Header (always visible, not collapsible)

| Panel | Type | Width | Query |
|-------|------|-------|-------|
| Clock | `grafana-clock-panel` | 4 | Current time |
| Cluster Uptime | Stat | 4 | `min(time() - node_boot_time_seconds{job="hypervisor-host"})` as duration |
| Total Running Jobs | Stat | 4 | Nomad running allocation count |
| Nodes Online | Stat | 4 | `count(up{job="nomad-client"} == 1)` |
| Alerts Firing | Stat | 4 | `count(ALERTS{alertstate="firing"})` — red if > 0 |
| Consul Services | Stat | 4 | `consul_catalog_services` |

### Row 1: Cluster Health (collapsible, default expanded)

**Sub-row 1a — Per-VM Node Overview (3 columns):**

For each VM (octant-01, 02, 03):
- CPU Usage — Gauge (0-100%), thresholds: green < 60%, amber 60-85%, red > 85%
- Memory Usage — Gauge (0-100%), same thresholds
- Root Disk Usage — Gauge (0-100%), thresholds: green < 70%, amber 70-85%, red > 85%

Queries use `node_cpu_seconds_total`, `node_memory_MemAvailable_bytes`, `node_filesystem_avail_bytes` filtered by instance.

**Sub-row 1b — Nomad & Consul Status:**

| Panel | Type | Width | Query |
|-------|------|-------|-------|
| Nomad Raft Peers | Stat (green if 3) | 6 | `nomad_nomad_raft_peers` |
| Consul Raft Peers | Stat (green if 3) | 6 | `consul_raft_peers` |
| Nomad Allocations | Stat grid | 6 | Running/pending/failed counts |
| Scheduler Pressure | Time series | 6 | `nomad_nomad_scheduler_eval_queue_depth` |

### Row 2: GPU Accelerator — 8x MI300X (collapsible, default expanded)

**Sub-row 2a — Summary Stats:**

| Panel | Type | Width | Query |
|-------|------|-------|-------|
| GPU Count | Stat | 3 | `amd_gpu_nodes_total` |
| Total VRAM | Stat | 3 | `sum(amd_gpu_total_vram) / 1024` (GiB) |
| VRAM Used | Stat | 3 | `sum(amd_gpu_used_vram) / 1024` (GiB) |
| Healthy GPUs | Stat | 3 | `sum(amd_gpu_health)` — "8/8" green |
| Driver Version | Stat | 3 | Label extract: `driver_version` from `amd_gpu_health` |
| Total Power | Stat | 3 | `sum(amd_gpu_package_power)` (W) |
| Avg Junction Temp | Stat | 3 | `avg(amd_gpu_junction_temperature)` — green < 70, amber 70-85, red > 85 |
| Avg GFX Activity | Stat | 3 | `avg(amd_gpu_gfx_activity)` (%) |

**Sub-row 2b — Per-GPU Bar Gauges:**

| Panel | Type | Width | Query |
|-------|------|-------|-------|
| GFX Activity by GPU | Bar gauge (horizontal, 8 bars) | 12 | `amd_gpu_gfx_activity` by `gpu_id` |
| VRAM Usage by GPU | Bar gauge (horizontal, 8 bars) | 12 | `amd_gpu_used_vram / amd_gpu_total_vram * 100` by `gpu_id` |

**Sub-row 2c — Time Series:**

| Panel | Type | Width | Query |
|-------|------|-------|-------|
| GPU Utilization Over Time | Time series (8 lines) | 12 | `amd_gpu_gfx_activity` by `gpu_id` |
| Junction Temperature | Time series (8 lines) | 12 | `amd_gpu_junction_temperature` by `gpu_id` |

### Row 3: Service Catalog (collapsible, default expanded)

**Sub-row 3a — Overview Stats:**

| Panel | Type | Width | Query |
|-------|------|-------|-------|
| Running Jobs | Stat (green) | 4 | Running allocation count |
| Total Services | Stat | 4 | `consul_catalog_services` |
| Scrape Targets Up | Stat | 4 | `count(up == 1) / count(up) * 100` |
| Alerts Firing | Stat (red if > 0) | 4 | `count(ALERTS{alertstate="firing"})` |
| Gatus Healthy | Stat | 4 | Gatus endpoint metrics (if available) |
| CephFS Disk | Gauge | 4 | `node_filesystem_avail_bytes{mountpoint="/mnt/services"}` |

**Sub-row 3b — Service Health Table:**

Table panel showing `up{job=~".*"}` with columns: Service Name, Status (up/down), Uptime %, Last Scrape. Green/red status dots, filterable and sortable.

**Sub-row 3c — Nomad Job Visualization:**

| Panel | Type | Width | Content |
|-------|------|-------|---------|
| Jobs by Status | Pie chart | 12 | Running vs Dead vs Pending allocations |
| Allocation Distribution | Bar chart | 12 | Allocations per node — workload spread |

### Row 4: AI / LLM Stack (collapsible, default expanded)

**Sub-row 4a — AI Service Status:**

| Panel | Type | Width | Query |
|-------|------|-------|-------|
| LiteLLM | Stat (up/down) | 4 | `up{job="litellm"}` or Consul health |
| Open WebUI | Stat (up/down) | 4 | `up{job="open-webui"}` or Consul health |
| Phoenix | Stat (up/down) | 4 | `up{job="phoenix"}` or Consul health |
| Neo4j | Stat (up/down) | 4 | `up{job="neo4j"}` or Consul health |
| Graphiti | Stat (up/down) | 4 | `up{job="graphiti"}` or Consul health |
| Qdrant | Stat (up/down) | 4 | `up{job="qdrant"}` or Consul health |

**Sub-row 4b — LLM Traffic (conditional on LiteLLM metrics availability):**

| Panel | Type | Width | Content |
|-------|------|-------|---------|
| LLM Requests/min | Time series | 8 | Request rate to LiteLLM |
| Model Usage | Pie chart | 8 | Requests by model name |
| Token Throughput | Stat | 8 | Tokens/sec |

Falls back to a text/markdown panel summarizing the AI stack if metrics aren't available.

**Sub-row 4c — Tempo Traces:**

| Panel | Type | Width | Content |
|-------|------|-------|---------|
| Trace Volume | Time series | 12 | `tempo_distributor_spans_received_total` rate |
| Service Map | Node graph | 12 | Tempo service map visualization |

### Row 5: Observability (collapsible, default collapsed)

| Panel | Type | Width | Query |
|-------|------|-------|-------|
| Prometheus Targets | Stat | 4 | `count(up == 1)` / `count(up)` |
| Loki Ingestion Rate | Stat | 4 | `sum(rate(loki_distributor_bytes_received_total[5m]))` |
| Log Volume | Time series | 8 | `sum(rate(loki_distributor_lines_received_total[5m]))` |
| Tempo Trace Rate | Stat | 4 | `sum(rate(tempo_distributor_spans_received_total[5m]))` |
| Storage Usage | Bar gauge | 8 | Prometheus data size + CephFS usage |

## Visual Design

- **Theme:** Dark theme compatible (default Grafana dark)
- **Color scheme:** Green = healthy/low, amber = warning, red = critical/high
- **Stat panels:** Colored backgrounds, large text for projection readability
- **Gauges:** Circular for CPU/memory/disk, with labeled thresholds
- **Time series:** Clean lines, GPU panels use 8-color palette to distinguish GPUs
- **Tables:** Alternating row colors, status dots, sortable columns

## Prerequisites

1. **Per-VM node exporters** must be in Prometheus scrape config — if not already, add `octant-01:9100`, `octant-02:9100`, `octant-03:9100` as targets
2. **GPU metrics exporter** must be running on hypervisor (192.168.122.1:5050) — already operational
3. **Grafana provisioning** directory must be configured in the Nomad job to load dashboard JSON on startup
4. Some AI service panels will gracefully show "No data" if services don't expose Prometheus metrics

## Implementation Notes

- Dashboard JSON file at `terraform/grafana/dashboards/octant-overview.json`
- Provisioning config added to Grafana Nomad job to mount dashboards directory
- Use `templatefile()` if any dashboard values need Terraform substitution (unlikely — most queries are static PromQL)
- The `grafana-clock-panel` plugin is already pre-installed
