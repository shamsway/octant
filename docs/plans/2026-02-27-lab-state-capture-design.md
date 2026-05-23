# Lab State Capture - Design

**Date:** 2026-02-27
**Branch:** `feature/app-migration`
**Status:** Approved

## Goal

Capture a point-in-time snapshot of all installed software versions and deployed container images in the Octant lab, producing both machine-readable JSON and human-readable markdown.

## Context

The Octant lab runs a 3-node Consul/Nomad cluster with Ceph storage, deploying 30+ containerized services via Terraform/Nomad. Today there is no single artifact that records the installed state of the cluster — versions are spread across APT packages, running binaries, and Terraform variable defaults. The health check playbook (`04-health-check.yml`) validates that services are running but does not capture version details or image tags. This design adds a state capture mechanism that runs on-demand and automatically after deployments.

## Architecture

```
                    playbooks/07-capture-state.yml
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                      │
   Ansible Facts         API Queries           Terraform Scan
   (per-host)         (run_once on             (local, delegate_to)
        │              octant-01)                     │
   ┌────┴────┐      ┌────┴────┐          ┌──────────┴──────────┐
   │pkg_facts│      │Nomad API│          │Parse variables.tf   │
   │svc_facts│      │Consul   │          │for image defaults   │
   │setup    │      │Ceph CLI │          └──────────┬──────────┘
   └────┬────┘      └────┬────┘                     │
        │                │                          │
        └────────┬───────┴──────────────────────────┘
                 │
        Save JSON to docs/state/lab-state.json
                 │
        scripts/state-to-markdown.py
                 │
        Save MD to docs/state/lab-state.md
```

Three categories of data are gathered:

1. **Per-host facts** — `gather_facts` + `package_facts` + `service_facts` provide OS, kernel, hardware, and installed package versions (consul, nomad, podman, ceph-common) automatically
2. **Cluster-level state** — API calls to Nomad (`/v1/jobs`, `/v1/job/<id>/allocations`), Consul (`/v1/agent/self`, `/v1/agent/members`), and `ceph status --format json` run once on the first server
3. **Intended image state** — A local task parses `terraform/*/variables.tf` to extract image variable defaults, enabling drift detection against live Nomad allocations

All data is assembled into a single JSON structure written to `docs/state/lab-state.json`. A Python script (`scripts/state-to-markdown.py`) reads the JSON and renders `docs/state/lab-state.md`.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Package versions | `package_facts` module | Free, reliable, no shell parsing — covers consul, nomad, podman, ceph-common |
| Service states | `service_facts` module | Cleaner than shelling out to `systemctl`, gives enabled/running in one call |
| Consul/Nomad versions | API + package_facts | API confirms the *running* version; package_facts shows *installed* — catches restart-pending upgrades |
| Ceph details | `ceph status --format json` | Structured output: version + health + OSD count in one call |
| Live job images | Nomad API `/v1/job/<id>/allocations` | Only way to get the actual pulled image per allocation |
| Intended images | Parse `terraform/*/variables.tf` | Static scan, works offline, enables drift detection |
| JSON-to-markdown | Python script | Ansible's `template` module can render markdown but Python handles tables, sorting, and conditional formatting much more cleanly |
| Output location | `docs/state/` | Keeps state artifacts together, git-trackable |
| Trigger | On-demand + post-deployment | Makefile target for ad-hoc use; auto-import at end of `03-deploy-services.yml` |

## What Gets Changed

| Component | Current State | Target State | Notes |
|-----------|--------------|--------------|-------|
| `playbooks/07-capture-state.yml` | Does not exist | New playbook | Gathers all facts and API data, writes JSON |
| `scripts/state-to-markdown.py` | Does not exist | New script | Converts JSON to formatted markdown |
| `docs/state/` | Does not exist | New directory | Contains `lab-state.json` and `lab-state.md` |
| `playbooks/03-deploy-services.yml` | Deploys services only | Imports `07-capture-state.yml` at end | Auto-capture after deployment |
| `Makefile` | No capture target | Adds `capture-state` target | On-demand usage |

## Data Model

```json
{
  "captured_at": "2026-02-27T14:30:00Z",
  "cluster": {
    "consul": { "version": "1.17.3", "members": [...], "leader": "..." },
    "nomad": { "version": "1.7.7", "members": [...], "leader": "..." },
    "ceph": {
      "version": "18.2.4",
      "codename": "reef",
      "health": "HEALTH_OK",
      "osds": 3,
      "pools": [...]
    }
  },
  "hosts": {
    "octant-01": {
      "os": "Debian 12 (bookworm)",
      "kernel": "6.1.0-27-amd64",
      "ram_mb": 8192,
      "vcpus": 2,
      "packages": {
        "consul": "1.17.3",
        "nomad": "1.7.7",
        "podman": "4.3.1+ds1-8+b1",
        "ceph-common": "18.2.4-1",
        "nomad-driver-podman": "0.6.4"
      },
      "services": {
        "consul-server": "running",
        "nomad-server": "running",
        "nomad-agent": "running"
      }
    }
  },
  "jobs": {
    "traefik": {
      "status": "running",
      "type": "service",
      "image_live": "docker.io/traefik:v3.3.5",
      "image_intended": "docker.io/traefik:v3.3.5",
      "node": "octant-02"
    }
  }
}
```

## Non-Goals

- Historical state tracking (git history provides this naturally via diffs to the committed JSON/markdown)
- Alerting on drift (this captures state; monitoring is a separate concern)
- Capturing 1Password secrets or sensitive credentials
- Terraform state file contents (too verbose, contains secrets)

## Validation

- `make capture-state` produces both `docs/state/lab-state.json` and `docs/state/lab-state.md`
- JSON is valid and parseable with `python3 -m json.tool`
- Markdown contains tables for: host versions, service states, cluster health, and deployed images with drift indicators
- `make deploy-services` automatically runs state capture at the end
