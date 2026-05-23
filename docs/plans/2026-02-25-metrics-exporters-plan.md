# Metrics Exporters & Prometheus Auto-Discovery Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add node-exporter and podman-exporter Ansible roles (ported from octant-private) and replace individual Prometheus scrape jobs with a Consul SD catch-all for `"metrics"`-tagged services.

**Architecture:** Two new Ansible roles deploy host-level (node-exporter) and container-level (podman-exporter) metrics exporters on all cluster nodes. Each registers itself as a Consul service with a `"metrics"` tag. A single Prometheus catch-all scrape job discovers all `"metrics"`-tagged Consul services, replacing four individual scrape configs.

**Tech Stack:** Ansible roles, systemd units, Podman containers, Consul service registration (JSON), Prometheus Consul SD, Nomad HCL templates

---

### Task 1: Create the node-exporter Ansible role

**Files:**
- Create: `roles/node-exporter/tasks/main.yml`
- Create: `roles/node-exporter/defaults/main.yml`

**Context:** This role is ported from `/home/melliott/git/octant-private/roles/node-exporter/`. The octant-private version uses `configdirs['consul-agent']` which resolves to `/opt/octant/config/consul-agent.d` in this repo's `inventory/group_vars/all.yml`. The only change from the source is adding a `"metrics"` tag to the Consul registration so the catch-all scrape job discovers it.

**Step 1: Create the role defaults**

```yaml
# roles/node-exporter/defaults/main.yml
---
node_exporter_port: 9100
```

**Step 2: Create the role tasks**

```yaml
# roles/node-exporter/tasks/main.yml
---
- name: Install Prometheus Node Exporter
  ansible.builtin.apt:
    name: prometheus-node-exporter
    state: present
    update_cache: yes

- name: Reload systemd daemon
  ansible.builtin.systemd:
    daemon_reload: true

- name: Start and enable Node Exporter service
  ansible.builtin.systemd:
    name: prometheus-node-exporter
    state: started
    enabled: true

- name: Create Consul service definition for node-exporter
  ansible.builtin.copy:
    content: |
      {
        "service": {
          "name": "node-exporter",
          "tags": ["metrics"],
          "port": {{ node_exporter_port }},
          "check": {
            "http": "http://localhost:{{ node_exporter_port }}/metrics",
            "interval": "30s",
            "timeout": "5s"
          }
        }
      }
    dest: "{{ configdirs['consul-agent'] }}/node-exporter.json"
    owner: "{{ user }}"
    group: "{{ group }}"
    mode: "0644"
  register: node_exporter_consul_def

- name: Reload consul-agent to register node-exporter
  ansible.builtin.command:
    cmd: consul reload -http-addr=127.0.0.1:{{ consul.ports.agent_http }}
  when: node_exporter_consul_def.changed
  changed_when: true
```

**Step 3: Commit**

```bash
git add roles/node-exporter/
git commit -m "feat(roles): add node-exporter role with Consul registration"
```

---

### Task 2: Create the podman-exporter Ansible role

**Files:**
- Create: `roles/podman-exporter/defaults/main.yml`
- Create: `roles/podman-exporter/tasks/main.yml`
- Create: `roles/podman-exporter/templates/podman-exporter-rootless.service.j2`
- Create: `roles/podman-exporter/templates/podman-exporter-rootful.service.j2`
- Create: `roles/podman-exporter/templates/podman-exporter-rootless-consul.json.j2`
- Create: `roles/podman-exporter/templates/podman-exporter-rootful-consul.json.j2`

**Context:** Ported from `/home/melliott/git/octant-private/roles/podman-exporter/`. Uses `configdirs['consul-agent']` and `configdirs['consul-agent-root']` from group_vars. The rootless exporter registers with the user-level consul-agent; the rootful exporter registers with consul-agent-root. Both Consul registrations already include the `"metrics"` tag.

**Step 1: Create role defaults**

```yaml
# roles/podman-exporter/defaults/main.yml
---
podman_exporter_image: "quay.io/navidys/prometheus-podman-exporter:v1.20.0"
podman_exporter_enable_rootless: true
podman_exporter_enable_rootful: true
podman_exporter_rootless_port: 9883
podman_exporter_rootful_port: 9882
podman_exporter_container_port: 9882
```

**Step 2: Create the rootless systemd unit template**

```ini
# roles/podman-exporter/templates/podman-exporter-rootless.service.j2
[Unit]
Description=Prometheus Podman Exporter (rootless)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User={{ user }}
Group={{ group }}
Environment=XDG_RUNTIME_DIR=/run/user/{{ uid }}
ExecStart=/usr/bin/podman run --name podman-exporter-rootless --replace --userns=keep-id --security-opt label=disable -p {{ podman_exporter_rootless_port }}:{{ podman_exporter_container_port }} -e CONTAINER_HOST=unix:///run/podman/podman.sock -e HOME=/tmp -v /run/user/{{ uid }}/podman/podman.sock:/run/podman/podman.sock:ro {{ podman_exporter_image }}
ExecStop=/usr/bin/podman stop -t 10 podman-exporter-rootless
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

**Step 3: Create the rootful systemd unit template**

```ini
# roles/podman-exporter/templates/podman-exporter-rootful.service.j2
[Unit]
Description=Prometheus Podman Exporter (rootful)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/podman run --name podman-exporter-rootful --replace --user 0 --security-opt label=disable -p {{ podman_exporter_rootful_port }}:{{ podman_exporter_container_port }} -e CONTAINER_HOST=unix:///run/podman/podman.sock -v /run/podman/podman.sock:/run/podman/podman.sock:ro {{ podman_exporter_image }}
ExecStop=/usr/bin/podman stop -t 10 podman-exporter-rootful
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

**Step 4: Create the rootless Consul registration template**

```json
// roles/podman-exporter/templates/podman-exporter-rootless-consul.json.j2
{
  "service": {
    "name": "podman-exporter-rootless",
    "id": "podman-exporter-rootless",
    "tags": ["metrics", "podman", "rootless"],
    "port": {{ podman_exporter_rootless_port }},
    "checks": [
      {
        "id": "podman-exporter-rootless-metrics",
        "name": "Podman Exporter (rootless) metrics",
        "http": "http://127.0.0.1:{{ podman_exporter_rootless_port }}/metrics",
        "interval": "30s",
        "timeout": "5s"
      }
    ]
  }
}
```

**Step 5: Create the rootful Consul registration template**

```json
// roles/podman-exporter/templates/podman-exporter-rootful-consul.json.j2
{
  "service": {
    "name": "podman-exporter-rootful",
    "id": "podman-exporter-rootful",
    "tags": ["metrics", "podman", "rootful"],
    "port": {{ podman_exporter_rootful_port }},
    "checks": [
      {
        "id": "podman-exporter-rootful-metrics",
        "name": "Podman Exporter (rootful) metrics",
        "http": "http://127.0.0.1:{{ podman_exporter_rootful_port }}/metrics",
        "interval": "30s",
        "timeout": "5s"
      }
    ]
  }
}
```

**Step 6: Create the role tasks**

```yaml
# roles/podman-exporter/tasks/main.yml
---
- name: Deploy rootless podman exporter systemd unit
  ansible.builtin.template:
    src: podman-exporter-rootless.service.j2
    dest: /etc/systemd/system/podman-exporter-rootless.service
    mode: "0644"
  register: podman_exporter_rootless_unit
  when: podman_exporter_enable_rootless

- name: Remove rootless podman exporter systemd unit when disabled
  ansible.builtin.file:
    path: /etc/systemd/system/podman-exporter-rootless.service
    state: absent
  when: not podman_exporter_enable_rootless

- name: Deploy rootful podman exporter systemd unit
  ansible.builtin.template:
    src: podman-exporter-rootful.service.j2
    dest: /etc/systemd/system/podman-exporter-rootful.service
    mode: "0644"
  register: podman_exporter_rootful_unit
  when: podman_exporter_enable_rootful

- name: Remove rootful podman exporter systemd unit when disabled
  ansible.builtin.file:
    path: /etc/systemd/system/podman-exporter-rootful.service
    state: absent
  when: not podman_exporter_enable_rootful

- name: Register rootless podman exporter service in Consul
  ansible.builtin.template:
    src: podman-exporter-rootless-consul.json.j2
    dest: "{{ configdirs['consul-agent'] }}/podman-exporter-rootless.json"
    owner: "{{ user }}"
    group: "{{ group }}"
    mode: "0644"
  register: podman_exporter_rootless_consul
  when: podman_exporter_enable_rootless

- name: Remove rootless podman exporter Consul service when disabled
  ansible.builtin.file:
    path: "{{ configdirs['consul-agent'] }}/podman-exporter-rootless.json"
    state: absent
  when: not podman_exporter_enable_rootless

- name: Register rootful podman exporter service in Consul
  ansible.builtin.template:
    src: podman-exporter-rootful-consul.json.j2
    dest: "{{ configdirs['consul-agent-root'] }}/podman-exporter-rootful.json"
    owner: root
    group: root
    mode: "0644"
  register: podman_exporter_rootful_consul
  when: podman_exporter_enable_rootful

- name: Remove rootful podman exporter Consul service when disabled
  ansible.builtin.file:
    path: "{{ configdirs['consul-agent-root'] }}/podman-exporter-rootful.json"
    state: absent
  when: not podman_exporter_enable_rootful

- name: Reload systemd daemon
  ansible.builtin.systemd:
    daemon_reload: true
  when: >-
    (podman_exporter_rootless_unit is defined and podman_exporter_rootless_unit.changed)
    or (podman_exporter_rootful_unit is defined and podman_exporter_rootful_unit.changed)

- name: Ensure rootless podman exporter is enabled and running
  ansible.builtin.systemd:
    name: podman-exporter-rootless
    state: started
    enabled: true
  when: podman_exporter_enable_rootless

- name: Ensure rootless podman exporter is disabled when not enabled
  ansible.builtin.systemd:
    name: podman-exporter-rootless
    state: stopped
    enabled: false
  failed_when: false
  when: not podman_exporter_enable_rootless

- name: Ensure rootful podman exporter is enabled and running
  ansible.builtin.systemd:
    name: podman-exporter-rootful
    state: started
    enabled: true
  when: podman_exporter_enable_rootful

- name: Ensure rootful podman exporter is disabled when not enabled
  ansible.builtin.systemd:
    name: podman-exporter-rootful
    state: stopped
    enabled: false
  failed_when: false
  when: not podman_exporter_enable_rootful

- name: Restart consul-agent when rootless exporter service definition changes
  ansible.builtin.systemd:
    name: consul-agent
    state: restarted
  when: podman_exporter_rootless_consul is defined and podman_exporter_rootless_consul.changed

- name: Restart consul-agent-root when rootful exporter service definition changes
  ansible.builtin.systemd:
    name: consul-agent-root
    state: restarted
  when: podman_exporter_rootful_consul is defined and podman_exporter_rootful_consul.changed
```

**Step 7: Commit**

```bash
git add roles/podman-exporter/
git commit -m "feat(roles): add podman-exporter role with rootless/rootful support"
```

---

### Task 3: Add roles to octant.yml playbook

**Files:**
- Modify: `octant.yml:71-72` (after the `restic` role entry)

**Context:** Both roles go after `restic` and before `post_tasks`. The node-exporter role runs unconditionally on all servers. The podman-exporter role is conditional on `podman == true` (which is the default in group_vars).

**Step 1: Add role entries to octant.yml**

After the existing restic role block (line 72), add:

```yaml
    - role: node-exporter
      tags: node-exporter
    - role: podman-exporter
      tags: podman-exporter
      when: podman == true
```

**Step 2: Commit**

```bash
git add octant.yml
git commit -m "feat(playbook): add node-exporter and podman-exporter roles to octant.yml"
```

---

### Task 4: Replace individual Prometheus scrape jobs with catch-all

**Files:**
- Modify: `terraform/prometheus/prometheus.nomad.hcl:204-238` (the four individual scrape jobs)

**Context:** Lines 204-238 contain four individual scrape jobs: `node-exporter`, `podman-exporter`, `podman-exporter-rootless`, `podman-exporter-rootful`. Replace all four with a single catch-all that discovers any Consul service tagged `"metrics"`. The catch-all uses `__meta_consul_service` as the `job` label so each service retains its own job name in Prometheus.

**Step 1: Replace the four scrape jobs**

Remove the four jobs at lines 204-238 and replace with:

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

**Step 2: Update the NodeExporterDown alert**

The `NodeExporterDown` alert at line 284 references `job="node-exporter"`. With the catch-all, the job label is set from the Consul service name which will still be `node-exporter`. No change needed - the alert works as-is.

**Step 3: Commit**

```bash
git add terraform/prometheus/prometheus.nomad.hcl
git commit -m "feat(prometheus): replace individual scrape jobs with consul-metrics catch-all"
```

---

### Task 5: Deploy and verify

**Context:** This task is manual - run by the user, not by Claude. Deployment uses the existing Makefile targets.

**Step 1: Deploy the Ansible roles to all nodes**

```bash
# Deploy just the new roles (fast, targeted)
make deploy-role ROLE=node-exporter
make deploy-role ROLE=podman-exporter
```

**Step 2: Verify node-exporter is running on all nodes**

```bash
# SSH to any node and check
ssh admin@192.168.122.101 'systemctl status prometheus-node-exporter && curl -s localhost:9100/metrics | head -5'
```

**Step 3: Verify podman exporters are running**

```bash
ssh admin@192.168.122.101 'systemctl status podman-exporter-rootless && curl -s localhost:9883/metrics | head -5'
ssh admin@192.168.122.101 'systemctl status podman-exporter-rootful && curl -s localhost:9882/metrics | head -5'
```

**Step 4: Verify Consul service registrations**

```bash
# Check all three services are registered
curl -s http://192.168.122.101:8500/v1/catalog/service/node-exporter | jq '.[].ServiceTags'
curl -s http://192.168.122.101:8500/v1/catalog/service/podman-exporter-rootless | jq '.[].ServiceTags'
curl -s http://192.168.122.101:8500/v1/catalog/service/podman-exporter-rootful | jq '.[].ServiceTags'
```

Expected: Each returns entries with `"metrics"` in the tags array.

**Step 5: Redeploy Prometheus with catch-all config**

```bash
cd terraform/prometheus && terraform apply -auto-approve
```

**Step 6: Verify Prometheus is scraping the new targets**

Open `https://prometheus.lab.shamsway.net/targets` and confirm:
- `consul-metrics` job shows targets for node-exporter (3 instances), podman-exporter-rootless (3 instances), podman-exporter-rootful (3 instances)
- All targets show state UP

Alternatively via API:
```bash
curl -s 'http://192.168.122.101:9091/api/v1/targets' | jq '.data.activeTargets[] | select(.labels.job | test("node-exporter|podman-exporter")) | {job: .labels.job, instance: .labels.instance, health: .health}'
```

**Step 7: Verify alert rules resolve**

```bash
# DiskUsage alert should no longer be pending (node_filesystem metrics available)
curl -s 'http://192.168.122.101:9091/api/v1/rules' | jq '.data.groups[].rules[] | select(.name == "NodeExporterDown") | {name: .name, state: .state}'
```

Expected: `state: "inactive"` (not firing, because node-exporter is now UP).

---

### Task 6: Update progress tracker

**Files:**
- Modify: `docs/plans/2026-02-21-vm-deployment-progress.md`

**Step 1: Add entry to the "Bugs Fixed During App Migration" table**

Add a row for the metrics exporters work.

**Step 2: Update "Current State" section**

Add line:
```
- **Metrics exporters:** node-exporter (port 9100), podman-exporter rootless (9883) and rootful (9882) on all nodes; Prometheus catch-all via `"metrics"` Consul tag
```

**Step 3: Commit**

```bash
git add docs/plans/2026-02-21-vm-deployment-progress.md
git commit -m "docs: update progress tracker with metrics exporters"
```
