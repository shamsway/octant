# Demo Scripts

Step-by-step guided walkthroughs for exploring and demonstrating the Octant lab.

## Tour the Cluster

A guided walkthrough of the cluster's management interfaces.

### 1. Consul — Service Discovery

Open [consul.lab.shamsway.net](https://consul.lab.shamsway.net).

- **Services tab:** Shows all registered services. Each Nomad job appears as a Consul
  service with health checks.
- **Nodes tab:** Shows the 3 cluster nodes (octant-01, 02, 03) plus their agent
  instances (agent, agent-root).
- **Key/Value tab:** Browse `terraform/state/` to see Terraform state for each service.

### 2. Nomad — Workload Scheduling

Open [nomad.lab.shamsway.net](https://nomad.lab.shamsway.net).

- **Jobs tab:** Lists all deployed jobs with status. Click a job to see allocations.
- **Clients tab:** Shows the 3 nodes and their resource usage (CPU, memory).
- Click any running job → Allocations → click an allocation → Logs to see container output.

### 3. Grafana — Observability

Open [grafana.lab.shamsway.net](https://grafana.lab.shamsway.net).

- **Explore → Prometheus:** Query metrics like `up`, `node_cpu_seconds_total`, or
  `nomad_client_allocs_running`.
- **Explore → Loki:** Query logs with `{job="<service>"}` to see container logs.
- **Explore → Tempo:** Search traces by service name or trace ID.
- Import the Node Exporter Full dashboard (ID: `1860`) for host-level metrics.

### 4. Gatus — Health Checks

Open [gatus.lab.shamsway.net](https://gatus.lab.shamsway.net).

- Shows 11 monitored endpoints across three groups: monitoring, infrastructure, apps.
- Each endpoint shows uptime history and response time graphs.

### 5. Traefik — Reverse Proxy

Open [traefik.lab.shamsway.net](https://traefik.lab.shamsway.net).

- **HTTP Routers:** Lists all routing rules (`Host(...)` matchers).
- **HTTP Services:** Shows backend services and their health.
- Traefik auto-discovers services from Consul Catalog — no manual configuration needed.

---

## Deploy a New Service

A walkthrough of deploying a new service from the template.

### 1. Copy the Template

```bash
cp -r terraform/template terraform/my-service
cd terraform/my-service
```

### 2. Edit the Nomad Job

Edit `my-service.nomad.hcl`:
- Set the job name, image, and port
- Configure Consul service registration and health check
- Add Traefik tags for routing:
  ```hcl
  tags = [
    "traefik.enable=true",
    "traefik.http.routers.my-service.rule=Host(`my-service.lab.shamsway.net`)",
  ]
  ```

### 3. Add Host Volumes (if needed)

If the service needs persistent storage, add volumes to `inventory/groups.yml`:

```yaml
- name: my-service-data
  path: /mnt/services/my-service/data
  backup: true
```

Then create the directories:
```bash
make deploy-volumes
```

### 4. Deploy

```bash
terraform init
terraform plan
terraform apply
```

### 5. Verify

- Check Nomad UI: job should show `running`
- Check Consul UI: service should be registered with passing health checks
- Visit `https://my-service.lab.shamsway.net` (after adding DNS via `make tf-update-dns-lab`)

---

## Observe the Stack

A walkthrough of the monitoring and observability pipeline.

### 1. Metrics Pipeline

```
Podman containers → podman-exporter (rootless :9883, rootful :9882)
Node metrics → node-exporter (:9100)
         ↓
Prometheus (scrapes via Consul service discovery)
         ↓
Grafana (dashboards and alerting)
         ↓
Alertmanager (notification routing)
```

- Visit [prometheus.lab.shamsway.net/targets](https://prometheus.lab.shamsway.net/targets) to see all scrape targets
- Targets are discovered via the `consul-metrics` scrape job

### 2. Logs Pipeline

```
Podman containers → stdout/stderr
         ↓
Alloy (collects and ships logs)
         ↓
Loki (stores and indexes)
         ↓
Grafana (query and explore)
```

- In Grafana → Explore → select Loki datasource
- Query: `{job="my-service"}` to see logs from a specific service
- Loki is integrated with Tempo for correlating logs and traces

### 3. Traces Pipeline

```
Instrumented applications → OTLP
         ↓
Alloy (receives and forwards)
         ↓
Tempo (stores traces)
         ↓
Grafana (trace visualization)
```

- In Grafana → Explore → select Tempo datasource
- Search by service name or trace ID
- Tempo links to Loki logs and Prometheus metrics for the same time range

### 4. Health Monitoring

Two complementary systems:

- **Gatus** (internal): Monitors 11 endpoints from within the cluster. Pre-configured,
  checks run automatically.
- **Uptime Kuma** (external): Monitors service accessibility through the full
  HAProxy → Traefik → service path. Supports notifications via Slack, Discord, ntfy, etc.
