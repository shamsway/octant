# OpenClaw Metrics Integration - Design

**Date:** 2026-03-04
**Branch:** `feature/app-migration`
**Status:** Draft

## Goal

Add Prometheus metrics to the OpenClaw gateway by integrating the `openclaw-metrics` library via an OpenClaw plugin, enabling observability of sessions, token usage, WebSocket connections, queues, and health status.

## Context

The OpenClaw gateway (`terraform/openclaw-gateway/`) runs the Scotty hub agent on Nomad. It already exports traces via OpenTelemetry (`diagnostics-otel` plugin → `otel-collector.service.consul:4328`), but lacks Prometheus-style metrics for dashboarding and alerting.

[SeanZoR/openclaw-metrics](https://github.com/SeanZoR/openclaw-metrics) is a zero-dependency TypeScript library that adds a Prometheus `/metrics` endpoint to an OpenClaw gateway, exposing 30 metrics across 7 categories. It also ships a pre-built Grafana dashboard.

The library's integration guide assumes you own the HTTP server directly. Since OpenClaw's gateway owns its HTTP server internally, integration requires writing a thin OpenClaw plugin that uses the Plugin SDK's `registerHttpRoute()` API.

Prometheus is already running in the cluster.

## Architecture

```
Prometheus (existing, in cluster)
    ↓ scrape GET /metrics (every 15s)
OpenClaw Gateway (port 18789, Consul: openclaw-gateway.service.consul)
    ↓ Plugin SDK registerHttpRoute("/metrics")
openclaw-metrics-plugin (in-process TypeScript plugin)
    ↓ imports createMetricsHandler()
openclaw-metrics (npm library, zero deps)
    ↓ collectMetrics(dataSource)
Gateway internals via Plugin SDK api.*
```

**Fallback path (if auth blocks Prometheus scrape):**

```
Prometheus
    ↓ scrape GET /metrics (port 9090, no auth)
metrics-exporter sidecar (separate Nomad task, same group)
    ↓ GET /metrics with bearer token (localhost:18789, shared network)
OpenClaw Gateway
```

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Integration method | OpenClaw Plugin (primary) | In-process access to gateway internals; sanctioned extension point via Plugin SDK `registerHttpRoute()` |
| Fallback if auth blocks scrape | Sidecar exporter in same Nomad group | Shares network namespace, can auth to gateway, re-serves on unauthenticated port |
| Plugin location in image | Built into Dockerfile.base as extension | Follows existing pattern for `openclaw-rocketchat`, `memory-lancedb`, `diagnostics-otel` |
| Grafana dashboard | Import from openclaw-metrics repo | Pre-built, covers all 30 metrics with reasonable panels |
| Prometheus scrape discovery | Consul service tags on existing service | No new Consul service needed; add `prometheus` tags to existing `openclaw-gateway` service registration |

## What Gets Changed

| Component | Current State | Target State | Notes |
|-----------|--------------|--------------|-------|
| `image/Dockerfile.base` | No metrics plugin | Installs `openclaw-metrics` + plugin extension | New build step after existing plugin installs |
| `image/openclaw-metrics-plugin/` | Does not exist | Plugin source: `package.json` + `index.ts` | ~50-100 lines TypeScript |
| `config/openclaw.json` | No metrics plugin loaded | `openclaw-metrics-plugin` in `plugins.load` list | Plugin registration |
| `openclaw-gateway.nomad.hcl` | No Prometheus tags | Consul service tags for Prometheus scrape target | Enables auto-discovery |
| Grafana | No OpenClaw dashboard | Import `openclaw-dashboard.json` | Manual import step |
| `openclaw-gateway.nomad.hcl` (fallback) | Single task | Optional second task for sidecar exporter | Only if auth blocks scraping |

## Implementation Sections

### Section 1: Create the OpenClaw Plugin

Create `image/openclaw-metrics-plugin/` with:

**`package.json`:**
```json
{
  "name": "openclaw-metrics-plugin",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "openclaw-metrics": "latest"
  }
}
```

**`index.ts`:**
The plugin registers at load time:
1. Import `createMetricsHandler` from `openclaw-metrics`
2. Build a `MetricsDataSource` that reads from the Plugin SDK's `api` object (session manager, token tracker, process manager, etc.)
3. Call `api.registerHttpRoute({ path: "/metrics", handler, auth: "none", match: "exact" })` — the exact `auth` value needs verification against the Plugin SDK source

The `MetricsDataSource` getters will populate what the Plugin SDK exposes. Categories that aren't accessible via the SDK will be omitted (the library handles missing getters gracefully — all are optional).

### Section 2: Update Dockerfile.base

After the existing `openclaw-rocketchat` install block (~line 104), add:

```dockerfile
# ── Metrics plugin ──────────────────────────────────────────────────────────
# OpenClaw plugin exposing Prometheus /metrics endpoint via openclaw-metrics.
COPY terraform/openclaw-gateway/image/openclaw-metrics-plugin /tmp/openclaw-metrics-plugin
RUN cd /tmp/openclaw-metrics-plugin \
    && npm install --omit=dev --ignore-scripts \
    && cp -r /tmp/openclaw-metrics-plugin /app/extensions/openclaw-metrics-plugin \
    && rm -rf /tmp/openclaw-metrics-plugin
```

Note: The build context for Dockerfile.base is the OpenClaw repo root, not the octant repo. The plugin files need to be copied into the OpenClaw build context before building, or the COPY path adjusted. The `botctl image build` workflow handles build context — the plugin directory may need to be staged there.

**Alternative:** If the build context issue is complex, install the plugin at runtime via the `openclaw plugins install` pattern (like `openclaw-rocketchat`), which would require publishing the plugin to npm or a git repo first.

### Section 3: Update openclaw.json

Add the plugin to the plugins configuration:

```json
{
  "plugins": {
    "load": [
      ...existing plugins...,
      {
        "name": "openclaw-metrics-plugin",
        "enabled": true
      }
    ]
  }
}
```

The exact config key depends on how bundled extensions are loaded vs. CLI-installed plugins. Follow the same pattern used by `diagnostics-otel`.

### Section 4: Update Nomad Job for Prometheus Discovery

Add Consul service tags to the existing `openclaw-gateway` service registration in `openclaw-gateway.nomad.hcl`:

```hcl
service {
  name = "openclaw-gateway"
  port = "http"
  tags = [
    ...existing traefik tags...,
    "prometheus",
    "prometheus.scrape=true",
    "prometheus.path=/metrics",
    "prometheus.port=$${NOMAD_HOST_PORT_http}",
  ]
}
```

The exact tag format depends on how Prometheus is configured for service discovery in this cluster. If using `consul_sd_configs`, these tags enable filtering.

### Section 5: Grafana Dashboard Import

1. Download `grafana/openclaw-dashboard.json` from the openclaw-metrics repo
2. Import into the cluster's Grafana instance
3. Select the existing Prometheus data source
4. Verify panels populate after first scrape

### Section 6: Fallback — Sidecar Exporter (if needed)

If the Plugin SDK's `registerHttpRoute()` requires auth that blocks Prometheus scraping, add a second task to the Nomad group:

```hcl
task "metrics-exporter" {
  driver = "podman"
  config {
    image = "node:22-slim"
    ports = ["metrics"]
    command = "node"
    args   = ["/app/exporter.js"]
  }

  template {
    data = <<-EOF
      // Minimal exporter: fetch /metrics from gateway with auth, re-serve without auth
      ...
    EOF
    destination = "local/exporter.js"
  }

  env {
    GATEWAY_URL = "http://localhost:18789"
  }

  resources {
    cpu    = 128
    memory = 256
  }
}
```

Add a corresponding port and Consul service:
```hcl
port "metrics" { to = 9090 }
```

This is only implemented if Section 1-4 fails due to auth constraints.

## Non-Goals

- Custom metrics beyond what `openclaw-metrics` provides
- Alerting rules (can be added later in Prometheus)
- Push-based metrics via OTEL (the existing `diagnostics-otel` plugin handles traces; this design adds pull-based Prometheus metrics as a complementary signal)
- Publishing the plugin to npm (it's a local extension for this deployment)

## Validation

1. **Plugin loads successfully:**
   ```bash
   nomad alloc logs -job openclaw-gateway | grep -i metrics
   ```
   Expect plugin registration log message.

2. **Metrics endpoint responds:**
   ```bash
   curl -s http://openclaw-gateway.service.consul:18789/metrics | head -20
   ```
   Expect Prometheus text format output with `openclaw_process_uptime_seconds` and other gauges.

3. **Prometheus scrapes successfully:**
   Check Prometheus targets page for `openclaw-gateway` target in `UP` state.

4. **Grafana dashboard populates:**
   Open the imported OpenClaw dashboard and verify panels show data after 1-2 scrape intervals.
