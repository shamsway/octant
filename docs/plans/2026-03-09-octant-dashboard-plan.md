# Octant Lab Overview Dashboard — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy a provisioned Grafana dashboard that shows cluster health, GPU accelerator status, service catalog, AI/LLM stack, and observability at a glance.

**Architecture:** The dashboard JSON file is stored in the git repo at `terraform/grafana/dashboards/octant-overview.json`. A dashboard provider YAML tells Grafana to auto-load dashboards from a directory. Both files are injected into the container via Nomad template blocks (same pattern as existing datasource provisioning). No new Terraform providers needed.

**Tech Stack:** Grafana 12.3.3, Prometheus (PromQL), Nomad templatefile(), Podman

**Design doc:** `docs/plans/2026-03-09-octant-dashboard-design.md`

---

### Task 1: Create Dashboard Provider YAML

**Files:**
- Create: `terraform/grafana/grafana-dashboard-provider.yml`

**Step 1: Create the dashboard provider config**

This tells Grafana to auto-load JSON dashboards from a provisioning directory.

```yaml
apiVersion: 1

providers:
  - name: octant
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /etc/grafana/provisioning/dashboards/json
      foldersFromFilesStructure: false
```

**Step 2: Verify file is valid YAML**

Run: `python3 -c "import yaml; yaml.safe_load(open('terraform/grafana/grafana-dashboard-provider.yml'))"`
Expected: No output (valid YAML)

**Step 3: Commit**

```bash
git add terraform/grafana/grafana-dashboard-provider.yml
git commit -m "feat(grafana): add dashboard provisioning provider config"
```

---

### Task 2: Update Grafana Nomad Job for Dashboard Provisioning

**Files:**
- Modify: `terraform/grafana/grafana.nomad.hcl`
- Modify: `terraform/grafana/main.tf`

**Step 1: Update main.tf to load the dashboard provider and JSON**

Add two new `data.local_file` resources and pass their content to the Nomad job template. The complete `main.tf` should become:

```hcl
provider "nomad" {
  address = "http://${var.nomad}:4646"
}

data "local_file" "grafana_datasources" {
  filename = "${path.module}/grafana-datasources.yml"
}

data "local_file" "dashboard_provider" {
  filename = "${path.module}/grafana-dashboard-provider.yml"
}

data "local_file" "octant_dashboard" {
  filename = "${path.module}/dashboards/octant-overview.json"
}

resource "nomad_job" "grafana" {
  jobspec = templatefile("${path.module}/grafana.nomad.hcl", {
    region              = var.region
    datacenter          = var.datacenter
    image               = var.image
    domain              = var.domain
    certresolver        = var.certresolver
    servicename         = var.servicename
    dns                 = jsonencode(var.dns)
    datasources_yaml    = data.local_file.grafana_datasources.content
    dashboard_provider  = data.local_file.dashboard_provider.content
    dashboard_json      = data.local_file.octant_dashboard.content
  })
}
```

**Step 2: Update grafana.nomad.hcl to add template blocks and volume mounts**

Add two new template blocks after the existing datasources template, and add two volume mount entries.

After the existing template block (around line 90), add:

```hcl
      template {
        destination   = "local/dashboard-provider.yml"
        change_mode   = "noop"
        data          = <<EOT
${dashboard_provider}
EOT
      }

      template {
        destination   = "local/octant-overview.json"
        change_mode   = "noop"
        data          = <<EOT
${dashboard_json}
EOT
      }
```

Add two entries to the `volumes` list in `config {}` (after the existing two):

```hcl
          "local/dashboard-provider.yml:/etc/grafana/provisioning/dashboards/default.yml",
          "local/octant-overview.json:/etc/grafana/provisioning/dashboards/json/octant-overview.json",
```

The full volumes list should be:
```hcl
        volumes = [
          "/mnt/services/grafana/data:/var/lib/grafana",
          "local/datasources.yml:/etc/grafana/provisioning/datasources/lgtm.yml",
          "local/dashboard-provider.yml:/etc/grafana/provisioning/dashboards/default.yml",
          "local/octant-overview.json:/etc/grafana/provisioning/dashboards/json/octant-overview.json",
        ]
```

**Step 3: Verify HCL is valid**

Run: `cd terraform/grafana && nomad job validate <(cat grafana.nomad.hcl | sed 's/\${[^}]*}/placeholder/g') 2>&1 || echo "Validation will happen at terraform plan time"`

Note: Full validation requires Terraform variable substitution, so actual validation happens at `terraform plan`.

**Step 4: Commit**

```bash
git add terraform/grafana/grafana.nomad.hcl terraform/grafana/main.tf
git commit -m "feat(grafana): add dashboard provisioning to Nomad job"
```

---

### Task 3: Create Dashboard JSON — Header Row + Cluster Health

**Files:**
- Create: `terraform/grafana/dashboards/octant-overview.json`

This is the core dashboard JSON file. It will be built incrementally across tasks 3-6. Start with the dashboard shell, header row, and cluster health row.

**Step 1: Create the dashboards directory**

Run: `mkdir -p terraform/grafana/dashboards`

**Step 2: Create the initial dashboard JSON**

Create `terraform/grafana/dashboards/octant-overview.json` with the dashboard metadata, header panels, and cluster health row.

**Header panels (Row 0, y=0, always visible):**

| Panel | gridPos | Query |
|-------|---------|-------|
| Clock | x:0 y:0 w:4 h:4 | `grafana-clock-panel` type, 24h format |
| Cluster Uptime | x:4 y:0 w:4 h:4 | `time() - node_boot_time_seconds{job="hypervisor-host"}` with duration unit `dtdurations` |
| Running Jobs | x:8 y:0 w:4 h:4 | `nomad_nomad_job_status_running` |
| Nodes Online | x:12 y:0 w:4 h:4 | `count(up{job="nomad-client"} == 1) / 2` (divide by 2 since rootless+root agents per node, 6 total for 3 nodes) |
| Alerts Firing | x:16 y:0 w:4 h:4 | `count(ALERTS{alertstate="firing"}) OR on() vector(0)` — red threshold > 0 |
| Consul Services | x:20 y:0 w:4 h:4 | `count(count by (__name__)(consul_catalog_service_query))` or `consul_catalog_services` if available |

**Cluster Health row (Row 1, y=5, collapsed=false):**

Sub-row 1a — Per-VM gauges (3 columns of 3 panels each):

For each VM instance (`192.168.122.101`, `.102`, `.103`):
- CPU Gauge: `100 - (avg by (instance)(rate(node_cpu_seconds_total{mode="idle",job="node-exporter",instance=~"INST.*"}[5m])) * 100)`
- Memory Gauge: `100 * (1 - node_memory_MemAvailable_bytes{job="node-exporter",instance=~"INST.*"} / node_memory_MemTotal_bytes{job="node-exporter",instance=~"INST.*"})`
- Disk Gauge: `100 * (1 - node_filesystem_avail_bytes{job="node-exporter",instance=~"INST.*",mountpoint="/"} / node_filesystem_size_bytes{job="node-exporter",instance=~"INST.*",mountpoint="/"})`

Note: The job name is `node-exporter` (as confirmed by Prometheus `up` query). Instances are `192.168.122.101:9100`, `192.168.122.102:9100`, `192.168.122.103:9100`.

Sub-row 1b — Nomad & Consul status:
- Nomad Raft Peers: `nomad_raft_peers` — stat, green if == 3
- Consul Raft Peers: `consul_raft_peers` — stat, green if == 3
- Running Allocations: `sum(nomad_client_allocations_running)` — stat
- Failed Allocations: `sum(nomad_client_allocs_failed)` — stat, red if > 0

**Step 3: Validate JSON**

Run: `python3 -c "import json; json.load(open('terraform/grafana/dashboards/octant-overview.json')); print('Valid JSON')"`
Expected: `Valid JSON`

**Step 4: Commit**

```bash
git add terraform/grafana/dashboards/octant-overview.json
git commit -m "feat(grafana): add octant dashboard - header and cluster health rows"
```

---

### Task 4: Add GPU Accelerator Row to Dashboard

**Files:**
- Modify: `terraform/grafana/dashboards/octant-overview.json`

Add the GPU Accelerator row panels to the dashboard JSON.

**Step 1: Add GPU summary stat panels (sub-row 2a)**

| Panel | Query | Unit/Format |
|-------|-------|-------------|
| GPU Count | `amd_gpu_nodes_total{cluster_name="octant-lab"}` | none |
| Total VRAM | `sum(amd_gpu_total_vram{cluster_name="octant-lab"}) / 1024` | GiB |
| VRAM In Use | `sum(amd_gpu_used_vram{cluster_name="octant-lab"}) / 1024` | GiB |
| Healthy GPUs | `sum(amd_gpu_health{cluster_name="octant-lab"})` | `/8` suffix |
| Driver Version | `amd_gpu_health{gpu_id="0"}` — use label `driver_version` as display via legend/transform | string |
| Total Power | `sum(amd_gpu_power_usage{cluster_name="octant-lab"})` | Watts |
| Avg Junction Temp | `avg(amd_gpu_junction_temperature{cluster_name="octant-lab"})` | °C, thresholds: green < 70, amber 70, red 85 |
| Avg GFX Activity | `avg(amd_gpu_gfx_activity{cluster_name="octant-lab"})` | percent |

**Step 2: Add per-GPU bar gauges (sub-row 2b)**

- GFX Activity by GPU: `amd_gpu_gfx_activity{cluster_name="octant-lab"}` — bar gauge, horizontal, legend `{{gpu_id}}`
- VRAM Usage by GPU: `amd_gpu_used_vram{cluster_name="octant-lab"} / amd_gpu_total_vram{cluster_name="octant-lab"} * 100` — bar gauge, horizontal, legend `{{gpu_id}}`

**Step 3: Add GPU time series (sub-row 2c)**

- GPU Utilization Over Time: `amd_gpu_gfx_activity{cluster_name="octant-lab"}` — time series, 8 lines, legend `GPU {{gpu_id}}`
- Junction Temperature: `amd_gpu_junction_temperature{cluster_name="octant-lab"}` — time series, 8 lines, legend `GPU {{gpu_id}}`, unit °C

**Step 4: Validate JSON**

Run: `python3 -c "import json; d=json.load(open('terraform/grafana/dashboards/octant-overview.json')); print(f'Valid JSON, {len(d.get(\"panels\",[]))} panels')"`

**Step 5: Commit**

```bash
git add terraform/grafana/dashboards/octant-overview.json
git commit -m "feat(grafana): add GPU accelerator row - 8x MI300X metrics"
```

---

### Task 5: Add Service Catalog Row to Dashboard

**Files:**
- Modify: `terraform/grafana/dashboards/octant-overview.json`

**Step 1: Add service catalog stats (sub-row 3a)**

| Panel | Query |
|-------|-------|
| Running Allocs | `sum(nomad_client_allocations_running)` |
| Scrape Targets Up | `count(up == 1) / count(up) * 100` — percent gauge |
| Alerts Firing | `count(ALERTS{alertstate="firing"}) OR on() vector(0)` |
| CephFS Usage | `100 * (1 - node_filesystem_avail_bytes{job="hypervisor-host",mountpoint=~".*services.*"} / node_filesystem_size_bytes{job="hypervisor-host",mountpoint=~".*services.*"})` |

Note: CephFS mountpoint may need adjustment based on actual node exporter labels. If the hypervisor doesn't mount CephFS directly, use VM node-exporter instances instead: `node_filesystem_avail_bytes{job="node-exporter",mountpoint="/mnt/services"}`.

**Step 2: Add service health table (sub-row 3b)**

Table panel querying `up` metric with transformations:
- Query: `up`
- Columns: job (renamed "Service"), instance, value (renamed "Status" with value mappings: 1=Up/green, 0=Down/red)
- Sort by: Status ascending (down services first)

**Step 3: Add Nomad job visualizations (sub-row 3c)**

- Jobs by Status: Pie chart with queries for `nomad_nomad_job_status_running`, `nomad_nomad_job_status_dead`, `nomad_nomad_job_status_pending`
- Allocations per Node: Bar chart — `nomad_client_allocations_running` grouped by instance

**Step 4: Validate JSON and commit**

```bash
python3 -c "import json; d=json.load(open('terraform/grafana/dashboards/octant-overview.json')); print(f'Valid JSON, {len(d.get(\"panels\",[]))} panels')"
git add terraform/grafana/dashboards/octant-overview.json
git commit -m "feat(grafana): add service catalog row - health table and Nomad status"
```

---

### Task 6: Add AI/LLM Stack and Observability Rows

**Files:**
- Modify: `terraform/grafana/dashboards/octant-overview.json`

**Step 1: Add AI/LLM service status panels (Row 4, sub-row 4a)**

Six stat panels showing up/down for AI services. These services may not have dedicated Prometheus scrape jobs, so use Consul-based health checks where possible. For services with Prometheus metrics, use `up{job="SERVICE"}`. For others, use a text panel with "Check Consul" note.

Known scrape targets (from `up` query): None of the AI services (litellm, open-webui, phoenix, neo4j, graphiti, qdrant) appear in the Prometheus `up` targets. These panels should query the Consul catalog or use a static "service deployed" indicator.

Pragmatic approach: Use `probe_success` if blackbox exporter is configured, OR use stat panels with `nomad_nomad_job_summary_running{exported_job="SERVICE_NAME"}` which shows 1 if the Nomad job has running allocations.

Best available query: `nomad_nomad_job_summary_running{exported_job=~"litellm|open-webui|phoenix|neo4j|graphiti|qdrant"}` — this comes from the Nomad server metrics and tracks whether each job has running allocations.

**Step 2: Add Tempo trace volume (sub-row 4c)**

- Trace Ingestion Rate: `sum(rate(tempo_distributor_spans_received_total[5m]))` — time series
- Check if `tempo_distributor_spans_received_total` exists in Prometheus. If not, use `tempo_ingester_traces_created_total` or similar Tempo metric.

**Step 3: Add Observability row (Row 5, collapsed by default)**

| Panel | Query |
|-------|-------|
| Prometheus Targets Up | `count(up == 1)` with `/` + `count(up)` as suffix |
| Loki Ingestion | `sum(rate(loki_distributor_bytes_received_total[5m]))` — bytes/sec |
| Log Volume | `sum(rate(loki_distributor_lines_received_total[5m]))` — time series, lines/sec |
| Tempo Trace Rate | `sum(rate(tempo_distributor_spans_received_total[5m]))` — spans/sec |

Note: Check that `loki_distributor_*` metrics are available. If Loki doesn't expose these to Prometheus, substitute with other available Loki metrics or omit.

**Step 4: Validate JSON and commit**

```bash
python3 -c "import json; d=json.load(open('terraform/grafana/dashboards/octant-overview.json')); print(f'Valid JSON, {len(d.get(\"panels\",[]))} panels')"
git add terraform/grafana/dashboards/octant-overview.json
git commit -m "feat(grafana): add AI/LLM stack and observability rows"
```

---

### Task 7: Deploy and Verify

**Files:**
- None (deployment only)

**Step 1: Run terraform plan**

```bash
cd terraform/grafana
terraform plan
```

Expected: Shows changes to `nomad_job.grafana` resource (updated jobspec with new template blocks and volume mounts). No errors.

**Step 2: Apply**

```bash
terraform apply -auto-approve
```

Expected: Successfully updates the Grafana job. Nomad will restart the Grafana allocation with the new templates.

**Step 3: Wait for Grafana to come up**

```bash
nomad job status grafana
```

Expected: Job status "running", allocation healthy.

**Step 4: Verify dashboard is loaded**

```bash
curl -s "http://grafana.service.consul:3000/api/search?query=Octant" | python3 -m json.tool
```

Expected: Returns the "Octant Lab Overview" dashboard in the search results.

**Step 5: Verify dashboard renders**

Open `https://grafana.lab.shamsway.net` in browser, navigate to the "Octant Lab Overview" dashboard. Verify:
- Header row shows clock, uptime, jobs, nodes, alerts
- Cluster health shows per-VM CPU/memory/disk gauges
- GPU row shows 8x MI300X metrics (if exporter is running)
- Service catalog shows health table with green/red dots
- AI/LLM row shows service status
- Observability row is collapsed but expandable

**Step 6: Commit any fixes**

If panels need PromQL adjustments (wrong metric names, missing labels, etc.), fix the JSON and redeploy:
```bash
terraform apply -auto-approve
```

---

## Implementation Notes

- **Panel IDs:** Auto-increment starting from 1. Grafana handles ID conflicts gracefully.
- **Grid positions:** Grafana uses a 24-unit wide grid. Standard panel height is 8 units. Use `w:24` for full-width panels, `w:12` for half, `w:8` for third, etc.
- **Datasource references:** Use `{"type": "prometheus", "uid": "prometheus"}` (matching the UID in `grafana-datasources.yml`).
- **Color thresholds:** Use the `thresholds` object with `steps` array: `[{"color": "green", "value": null}, {"color": "#EAB839", "value": 60}, {"color": "red", "value": 85}]`.
- **Row panels:** Use `"type": "row"` with `"collapsed": false` (or `true` for observability). Child panels go in the `"panels"` array of the row.
- **Templatefile escaping:** The dashboard JSON contains `$` characters in PromQL queries. In the Nomad HCL template, these pass through fine since they're inside `${dashboard_json}` which is already the file content. No double-escaping needed — Terraform substitutes the variable, Nomad just writes the result.
- **Large JSON in template:** The dashboard JSON may be 2000+ lines. This is fine for Nomad templates — the content is just written to disk. No HCL parsing of the JSON content occurs.
