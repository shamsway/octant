# OpenClaw Metrics Integration - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Prometheus metrics to the OpenClaw gateway via an OpenClaw plugin wrapping the `openclaw-metrics` library.

**Architecture:** A thin OpenClaw plugin (`openclaw-metrics-plugin`) imports `createMetricsHandler` from the `openclaw-metrics` npm package and registers `/metrics` as an HTTP route via the Plugin SDK. Prometheus auto-discovers the endpoint via the existing `consul-metrics` catch-all scrape job (tag: `"metrics"`). A Grafana dashboard is imported from the openclaw-metrics repo.

**Tech Stack:** TypeScript (OpenClaw Plugin SDK), `openclaw-metrics` npm package, Nomad HCL, Terraform, Prometheus, Grafana

**Design doc:** `docs/plans/2026-03-04-openclaw-metrics-design.md`

---

### Task 1: Research Plugin SDK `registerHttpRoute` auth options

Before writing any code, verify that the Plugin SDK supports unauthenticated HTTP routes (required for Prometheus scraping).

**Files:**
- Read: OpenClaw source at `https://github.com/openclaw/openclaw` — search for `registerHttpRoute` in the Plugin SDK

**Step 1: Check the Plugin SDK source for auth parameter options**

```bash
# If source_repo is configured locally:
grep -r "registerHttpRoute\|HttpRouteOptions\|auth.*none\|auth.*public" ${SOURCE_REPO}/src/ --include="*.ts" -l

# Otherwise, search the GitHub repo:
gh search code "registerHttpRoute" --repo openclaw/openclaw --json path,textMatches
```

Look for:
- The type definition of the `auth` parameter on `registerHttpRoute`
- Whether `"none"` or `"public"` is a valid auth mode
- How existing plugins (like the built-in health endpoint) register their routes

**Step 2: Document findings**

Record what auth values are valid. If `"none"` is not supported, note this — Task 7 (sidecar fallback) becomes the primary path.

**Step 3: Check if openclaw-metrics itself has any Plugin SDK integration guidance**

```bash
gh api repos/SeanZoR/openclaw-metrics/contents/README.md --jq '.content' | base64 -d | grep -i plugin
```

**Expected outcome:** We know whether `auth: "none"` works, which determines whether we proceed with the plugin path or the sidecar fallback.

---

### Task 2: Create the OpenClaw metrics plugin

Write the plugin as a standalone npm package that can be installed into the OpenClaw extensions directory.

**Files:**
- Create: `terraform/openclaw-gateway/image/openclaw-metrics-plugin/package.json`
- Create: `terraform/openclaw-gateway/image/openclaw-metrics-plugin/index.ts`

**Step 1: Create the plugin directory**

```bash
mkdir -p terraform/openclaw-gateway/image/openclaw-metrics-plugin
```

**Step 2: Write package.json**

```json
{
  "name": "openclaw-metrics-plugin",
  "version": "1.0.0",
  "description": "OpenClaw plugin exposing Prometheus /metrics endpoint via openclaw-metrics",
  "type": "module",
  "main": "index.ts",
  "dependencies": {
    "openclaw-metrics": "^1.0.0"
  }
}
```

Note: The `main` field points to `.ts` because OpenClaw loads plugins via `jiti` (just-in-time TypeScript execution) — no compile step needed.

**Step 3: Write index.ts**

The plugin entry point. Adapt based on Task 1 findings for the `auth` parameter:

```typescript
import type { PluginAPI } from "openclaw"; // Adjust import based on actual SDK types
import { createMetricsHandler } from "openclaw-metrics";
import type { MetricsDataSource } from "openclaw-metrics";

export default function register(api: PluginAPI) {
  // Build data source from whatever the Plugin SDK exposes.
  // All getters are optional — omit categories the SDK doesn't provide.
  const dataSource: MetricsDataSource = {
    // Process metrics (uptime, memory) are collected automatically
    // by openclaw-metrics from Node.js process.* — no getter needed.

    // Wire up categories based on what api.* exposes:
    // getWsStats:      () => { ... },
    // getTokenUsage:   () => { ... },
    // getSessionStats: () => { ... },
    // getProcessStats: () => { ... },
    // getQueueStats:   () => { ... },
    // getHealthStats:  () => { ... },
  };

  const metricsHandler = createMetricsHandler(dataSource);

  // Register the /metrics HTTP route.
  // auth value depends on Task 1 findings.
  api.registerHttpRoute({
    path: "/metrics",
    match: "exact",
    auth: "none", // VERIFY: may need adjustment per Task 1
    handler: async (req, res) => {
      await metricsHandler(req, res);
    },
  });
}
```

**Important:** This is a skeleton. The `register` function signature, `PluginAPI` type, and `registerHttpRoute` parameters must be adjusted based on Task 1 findings. The data source getters are intentionally left as comments — they depend on what the Plugin SDK exposes. Even with no getters, the 4 process-level metrics (uptime, memory RSS, heap used, heap total) are always emitted.

**Step 4: Commit the plugin source**

```bash
git add terraform/openclaw-gateway/image/openclaw-metrics-plugin/
git commit -m "feat(openclaw-gateway): add openclaw-metrics plugin source"
```

---

### Task 3: Update Dockerfile.base to install the plugin

The build context is the **OpenClaw source repo** (not the octant repo), so we cannot `COPY` files from `terraform/openclaw-gateway/image/`. Instead, follow the `openclaw-rocketchat` pattern: install the plugin during the Docker build using `npm install` from the git repo.

**Files:**
- Modify: `terraform/openclaw-gateway/image/Dockerfile.base:104-106` (after the rocketchat plugin block)

**Step 1: Determine the install method**

Two options depending on whether the plugin is published:

**Option A — Install from local directory (requires staging into build context):**
The `botctl image build` command would need to copy the plugin directory into the OpenClaw source repo before building. Add this note to the Dockerfile and update the build script.

**Option B — Install from GitHub (no build context issue):**
If the plugin is pushed to a GitHub repo (e.g., as part of the octant repo or standalone), install directly:

```dockerfile
# ── Metrics plugin ──────────────────────────────────────────────────────────
# OpenClaw plugin exposing Prometheus /metrics endpoint via openclaw-metrics.
RUN npm install --prefix /tmp/openclaw-metrics-plugin openclaw-metrics \
    && mkdir -p /app/extensions/openclaw-metrics-plugin \
    && cp -r /tmp/openclaw-metrics-plugin/node_modules /app/extensions/openclaw-metrics-plugin/ \
    && rm -rf /tmp/openclaw-metrics-plugin
```

**Option C — Use openclaw CLI plugins install (if the plugin is published to npm):**
```dockerfile
RUN node openclaw.mjs plugins install openclaw-metrics-plugin \
    && cp -r /root/.openclaw/extensions/openclaw-metrics-plugin /app/extensions/openclaw-metrics-plugin
```

**Step 2: Choose the install method and add the Dockerfile block**

The most pragmatic approach for a local-only plugin: modify `botctl image build` to stage the plugin files into the build context, then COPY them. Add after line 106 in Dockerfile.base:

```dockerfile
# ── Metrics plugin ──────────────────────────────────────────────────────────
# OpenClaw plugin exposing Prometheus /metrics endpoint via openclaw-metrics.
# Plugin source is staged into the build context by botctl image build.
COPY .openclaw-metrics-plugin /app/extensions/openclaw-metrics-plugin
RUN cd /app/extensions/openclaw-metrics-plugin \
    && npm install --omit=dev --ignore-scripts
```

**Step 3: Update botctl image build to stage the plugin**

Modify `terraform/openclaw-gateway/lib/image.sh` function `_image_build()` to copy the plugin directory into the build context before running `podman build`:

```bash
# In _image_build(), before the podman build command for base image:
local plugin_src="${BOTCTL_DIR}/image/openclaw-metrics-plugin"
if [[ -d "${plugin_src}" ]]; then
  echo "==> Staging metrics plugin into build context"
  cp -r "${plugin_src}" "${ctx}/.openclaw-metrics-plugin"
  # Clean up after build (add to trap or post-build)
fi
```

Add cleanup after both build stages complete:

```bash
# After both builds complete:
rm -rf "${ctx}/.openclaw-metrics-plugin"
```

**Step 4: Add .openclaw-metrics-plugin to .gitignore in openclaw source**

This is a staged artifact in the build context — it should not be committed to the OpenClaw repo if using a local source_repo.

**Step 5: Commit**

```bash
git add terraform/openclaw-gateway/image/Dockerfile.base terraform/openclaw-gateway/lib/image.sh
git commit -m "feat(openclaw-gateway): install metrics plugin in container image"
```

---

### Task 4: Update openclaw.json to load the plugin

**Files:**
- Modify: `terraform/openclaw-gateway/config/openclaw.json`

**Step 1: Add the plugin to the plugins entries**

Add after the `diagnostics-otel` entry (line 167):

```json
"openclaw-metrics-plugin": { "enabled": true }
```

The full `plugins.entries` block becomes:

```json
"plugins": {
  "slots": {
    "memory": "memory-core"
  },
  "entries": {
    "rocketchat": { "enabled": true },
    "memory-core": { "enabled": true },
    "memory-lancedb": { "enabled": false },
    "lobster": { "enabled": true },
    "llm-task": { ... },
    "thread-ownership": { "enabled": false },
    "diagnostics-otel": { "enabled": true },
    "openclaw-metrics-plugin": { "enabled": true }
  }
}
```

**Step 2: Commit**

```bash
git add terraform/openclaw-gateway/config/openclaw.json
git commit -m "feat(openclaw-gateway): enable metrics plugin in openclaw.json"
```

---

### Task 5: Add Prometheus scrape tags to the Nomad job

The cluster's Prometheus has a catch-all `consul-metrics` scrape job that auto-discovers any Consul service tagged with `"metrics"`. Add this tag to the existing service registration.

**Files:**
- Modify: `terraform/openclaw-gateway/openclaw-gateway.nomad.hcl:27-34` (service tags block)

**Step 1: Add the `"metrics"` tag**

Update the `tags` array in the `service` block. Current tags (lines 27-34):

```hcl
tags = [
  "traefik.enable=true",
  "traefik.consulcatalog.connect=false",
  "traefik.http.routers.${servicename}.rule=Host(`openclaw.${domain}`)",
  "traefik.http.routers.${servicename}.entrypoints=web,websecure",
  "traefik.http.routers.${servicename}.tls.certresolver=${certresolver}",
  "traefik.http.routers.${servicename}.middlewares=redirect-web-to-websecure@internal",
]
```

Add `"metrics"` to the list:

```hcl
tags = [
  "traefik.enable=true",
  "traefik.consulcatalog.connect=false",
  "traefik.http.routers.${servicename}.rule=Host(`openclaw.${domain}`)",
  "traefik.http.routers.${servicename}.entrypoints=web,websecure",
  "traefik.http.routers.${servicename}.tls.certresolver=${certresolver}",
  "traefik.http.routers.${servicename}.middlewares=redirect-web-to-websecure@internal",
  "metrics",
]
```

**Step 2: Verify no conflicting Prometheus routes**

The catch-all scrape job defaults to `/metrics` path, which matches our plugin's registered route. No `metrics_path` override needed.

**Step 3: Commit**

```bash
git add terraform/openclaw-gateway/openclaw-gateway.nomad.hcl
git commit -m "feat(openclaw-gateway): add Prometheus scrape discovery tag"
```

---

### Task 6: Build, deploy, and validate

**Step 1: Build and push the new image**

```bash
cd terraform/openclaw-gateway
./botctl image deploy --auto-approve
```

This runs: Dockerfile.base build → Dockerfile.infra build → push to registry → terraform apply.

**Step 2: Deploy updated openclaw.json to CephFS**

The config is deployed out-of-band to CephFS:

```bash
./botctl config deploy
```

**Step 3: Restart the gateway to pick up new config**

```bash
./botctl gateway restart
```

**Step 4: Verify plugin loads**

```bash
./botctl gateway logs 2>&1 | grep -i metrics
```

Look for a plugin registration log message indicating `openclaw-metrics-plugin` loaded.

**Step 5: Verify /metrics endpoint responds**

```bash
curl -s http://openclaw-gateway.service.consul:18789/metrics | head -20
```

Expected output:
```
# HELP openclaw_process_uptime_seconds Process uptime in seconds
# TYPE openclaw_process_uptime_seconds gauge
openclaw_process_uptime_seconds 42.1
# HELP openclaw_process_memory_rss_bytes Resident set size in bytes
# TYPE openclaw_process_memory_rss_bytes gauge
openclaw_process_memory_rss_bytes 85983232
```

If this returns a 401/403, the auth parameter is blocking — proceed to Task 7 (sidecar fallback).

**Step 6: Verify Prometheus discovers the target**

Open Prometheus UI → Status → Targets. Look for `openclaw-gateway` in the `consul-metrics` job. Status should be `UP`.

**Step 7: Import Grafana dashboard**

```bash
# Download the dashboard JSON
curl -fsSL https://raw.githubusercontent.com/SeanZoR/openclaw-metrics/main/grafana/openclaw-dashboard.json \
  -o /tmp/openclaw-dashboard.json
```

Then in Grafana UI:
1. Dashboards → Import
2. Upload `/tmp/openclaw-dashboard.json`
3. Select the Prometheus data source
4. Verify panels populate after 1-2 scrape intervals (15-30 seconds)

---

### Task 7: Sidecar fallback (ONLY if Task 6 Step 5 returns auth error)

If the `/metrics` endpoint requires authentication that Prometheus can't provide, deploy a sidecar exporter.

**Files:**
- Modify: `terraform/openclaw-gateway/openclaw-gateway.nomad.hcl` (add port + task + service)

**Step 1: Add a metrics port to the network block**

```hcl
network {
  port "http" {
    to = 18789
  }
  port "metrics" {
    to = 9090
  }
  dns {
    servers = ${dns}
  }
}
```

**Step 2: Add a separate Consul service for the metrics exporter**

```hcl
service {
  name     = "openclaw-metrics"
  provider = "consul"
  port     = "metrics"

  tags = ["metrics"]

  check {
    name     = "metrics-alive"
    type     = "http"
    path     = "/metrics"
    port     = "metrics"
    interval = "30s"
    timeout  = "5s"
  }
}
```

**Step 3: Add the sidecar task**

```hcl
task "metrics-exporter" {
  driver = "podman"

  config {
    image = "node:22-slim"
    ports = ["metrics"]
    entrypoint = ["node"]
    args = ["$${NOMAD_TASK_DIR}/exporter.mjs"]
  }

  template {
    destination = "$${NOMAD_TASK_DIR}/exporter.mjs"
    data = <<-SCRIPT
import http from 'node:http';

const GATEWAY = process.env.GATEWAY_URL || 'http://localhost:18789';
const TOKEN = process.env.GATEWAY_TOKEN || '';
const PORT = parseInt(process.env.PORT || '9090', 10);

const server = http.createServer(async (req, res) => {
  if (req.url !== '/metrics' || req.method !== 'GET') {
    res.writeHead(404);
    res.end('Not found');
    return;
  }
  try {
    const headers = TOKEN ? { Authorization: `Bearer $${TOKEN}` } : {};
    const upstream = await fetch(`$${GATEWAY}/metrics`, { headers });
    if (!upstream.ok) {
      res.writeHead(502);
      res.end(`Upstream error: $${upstream.status}`);
      return;
    }
    const body = await upstream.text();
    res.writeHead(200, { 'Content-Type': 'text/plain; version=0.0.4; charset=utf-8' });
    res.end(body);
  } catch (err) {
    res.writeHead(502);
    res.end(`Fetch error: $${err.message}`);
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Metrics exporter listening on :$${PORT}`);
});
SCRIPT
  }

  template {
    destination = "$${NOMAD_SECRETS_DIR}/env.txt"
    env         = true
    data        = <<-EOT
{{- with nomadVar "nomad/jobs/openclaw-gateway" -}}
GATEWAY_TOKEN={{ .openclaw_gateway_token }}
{{- end -}}
EOT
  }

  env {
    GATEWAY_URL = "http://localhost:18789"
    PORT        = "9090"
  }

  resources {
    cpu    = 128
    memory = 256
  }
}
```

Note: `$${}` is used for Nomad runtime variable interpolation (escaped from Terraform's `${}`). The `fetch` API is available in Node.js 22+.

**Step 4: Deploy the updated Nomad job**

```bash
cd terraform/openclaw-gateway
terraform apply -auto-approve
```

**Step 5: Verify the sidecar serves metrics**

```bash
curl -s http://openclaw-metrics.service.consul:9090/metrics | head -20
```

**Step 6: Verify Prometheus discovers the sidecar**

Check Prometheus UI → Status → Targets for `openclaw-metrics` in the `consul-metrics` job.

**Step 7: Commit**

```bash
git add terraform/openclaw-gateway/openclaw-gateway.nomad.hcl
git commit -m "feat(openclaw-gateway): add metrics sidecar exporter as auth fallback"
```

---

### Task 8: Update design doc status

**Files:**
- Modify: `docs/plans/2026-03-04-openclaw-metrics-design.md:5`

**Step 1: Mark the design as approved/implemented**

Change line 5 from:
```
**Status:** Draft
```
to:
```
**Status:** Implemented
```

**Step 2: Commit all final changes**

```bash
git add docs/plans/2026-03-04-openclaw-metrics-design.md
git commit -m "docs(openclaw-gateway): mark metrics design as implemented"
```
