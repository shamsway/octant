# HAProxy Ingress Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy HAProxy on the hypervisor to load-balance traffic across the 3 octant VMs with active health checks.

**Architecture:** HAProxy runs on the hypervisor in TCP mode, proxying ports 443 (Traefik HTTPS), 4646 (Nomad API), and 8500 (Consul API) to all three VMs. Active health checks remove unresponsive backends. Implemented as an Ansible role applied via a new playbook in the deployment pipeline.

**Tech Stack:** HAProxy 2.x (Debian apt), Ansible role + Jinja2 template, Make

**Design doc:** `docs/plans/2026-02-24-haproxy-ingress-design.md`

---

### Task 1: Create HAProxy config template

**Files:**
- Create: `roles/haproxy/templates/haproxy.cfg.j2`

**Step 1: Create the template file**

```jinja2
global
    log /dev/log local0
    log /dev/log local1 notice
    maxconn 4096
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5s
    timeout client  30s
    timeout server  30s
    retries 3

# --- Traefik HTTPS (TCP passthrough) ---
frontend traefik_https_front
    bind *:443
    default_backend traefik_https_back

backend traefik_https_back
    balance roundrobin
    option tcp-check
{% for host in groups['servers'] %}
    server {{ host }} {{ hostvars[host].vm_ip }}:443 check inter 5s fall 3 rise 2
{% endfor %}

# --- Nomad API ---
frontend nomad_api_front
    bind *:4646
    default_backend nomad_api_back

backend nomad_api_back
    balance roundrobin
    option tcp-check
{% for host in groups['servers'] %}
    server {{ host }} {{ hostvars[host].vm_ip }}:{{ nomad.ports.http }} check inter 5s fall 3 rise 2
{% endfor %}

# --- Consul API ---
frontend consul_api_front
    bind *:8500
    default_backend consul_api_back

backend consul_api_back
    balance roundrobin
    option tcp-check
{% for host in groups['servers'] %}
    server {{ host }} {{ hostvars[host].vm_ip }}:{{ consul.ports.http }} check inter 5s fall 3 rise 2
{% endfor %}

# --- Stats (localhost only) ---
frontend stats_front
    bind 127.0.0.1:8404
    mode http
    default_backend stats_back

backend stats_back
    mode http
    stats enable
    stats uri /
    stats refresh 10s
```

**Step 2: Commit**

```bash
git add roles/haproxy/templates/haproxy.cfg.j2
git commit -m "feat(haproxy): add HAProxy config template with health checks"
```

---

### Task 2: Create HAProxy role tasks

**Files:**
- Create: `roles/haproxy/tasks/main.yml`

**Step 1: Create the tasks file**

```yaml
---
- name: Install HAProxy
  ansible.builtin.apt:
    name: haproxy
    state: present
    update_cache: true

- name: Deploy HAProxy configuration
  ansible.builtin.template:
    src: haproxy.cfg.j2
    dest: /etc/haproxy/haproxy.cfg
    owner: root
    group: root
    mode: "0644"
    validate: "haproxy -c -f %s"
  notify: restart haproxy

- name: Ensure HAProxy is enabled and started
  ansible.builtin.systemd:
    name: haproxy
    enabled: true
    state: started

- name: Verify HAProxy is listening
  ansible.builtin.wait_for:
    port: "{{ item }}"
    host: 127.0.0.1
    timeout: 15
  loop:
    - 443
    - 4646
    - 8500

- name: Display HAProxy status
  ansible.builtin.debug:
    msg: |
      HAProxy deployed on hypervisor:
        :443  -> {{ groups['servers'] | map('extract', hostvars, 'vm_ip') | join(', ') }} (Traefik HTTPS)
        :4646 -> {{ groups['servers'] | map('extract', hostvars, 'vm_ip') | join(', ') }} (Nomad API)
        :8500 -> {{ groups['servers'] | map('extract', hostvars, 'vm_ip') | join(', ') }} (Consul API)
        Stats: http://127.0.0.1:8404/
```

**Step 2: Commit**

```bash
git add roles/haproxy/tasks/main.yml
git commit -m "feat(haproxy): add role tasks - install, configure, verify"
```

---

### Task 3: Create the playbook

**Files:**
- Create: `playbooks/02.5-deploy-haproxy.yml`

**Step 1: Create the playbook**

```yaml
---
# Deploy HAProxy on hypervisor to load-balance traffic to VM cluster
# Proxies: 443 (Traefik), 4646 (Nomad), 8500 (Consul)
#
# Usage:
#   ansible-playbook playbooks/02.5-deploy-haproxy.yml -i inventory/hypervisors.yml -i inventory/groups.yml
#
# Prerequisites:
#   - VMs provisioned (01-provision-vms.yml)
#   - Cluster deployed (octant.yml) - Consul/Nomad listening

- name: Deploy HAProxy ingress on hypervisor
  hosts: hypervisors
  gather_facts: true
  become: true

  roles:
    - role: haproxy

  handlers:
    - name: restart haproxy
      ansible.builtin.systemd:
        name: haproxy
        state: restarted
```

**Step 2: Commit**

```bash
git add playbooks/02.5-deploy-haproxy.yml
git commit -m "feat(haproxy): add playbook targeting hypervisors"
```

---

### Task 4: Add Makefile target and pipeline integration

**Files:**
- Modify: `Makefile`

**Step 1: Add the deploy-haproxy target**

Add after `deploy-cluster` target (around line 117), before `deploy-ceph`:

```makefile
deploy-haproxy:
	ansible-playbook playbooks/02.5-deploy-haproxy.yml $(VM_INVENTORY)
```

Note: Uses `VM_INVENTORY` (`-i inventory/hypervisors.yml -i inventory/groups.yml`) because the playbook targets the hypervisor but needs the `servers` group from `groups.yml` for backend IPs.

**Step 2: Update the deploy-vm pipeline**

Change line 137 from:
```makefile
deploy-vm: build-base-image provision-vms deploy-cluster deploy-ceph deploy-services health-check
```
to:
```makefile
deploy-vm: build-base-image provision-vms deploy-cluster deploy-haproxy deploy-ceph deploy-services health-check
```

**Step 3: Update the .PHONY line**

Add `deploy-haproxy` to the `.PHONY` declaration on line 5.

**Step 4: Commit**

```bash
git add Makefile
git commit -m "feat(haproxy): add make target and pipeline integration"
```

---

### Task 5: Test the deployment

**Step 1: Run the playbook**

```bash
make deploy-haproxy
```

Expected: HAProxy installs, config validates, service starts, all 3 ports listening.

**Step 2: Verify HAProxy is routing traffic**

From the hypervisor:

```bash
# Check HAProxy is listening
ss -tlnp | grep -E ':(443|4646|8500)\s'

# Check stats page (shows backend health)
curl -s http://127.0.0.1:8404/ | grep -E 'UP|DOWN'

# Test Consul API through HAProxy
curl -s http://localhost:8500/v1/status/leader

# Test Nomad API through HAProxy
curl -s http://localhost:4646/v1/status/leader
```

**Step 3: Verify health checks**

```bash
# Show backend status via stats
curl -s http://127.0.0.1:8404/\;csv | grep -E 'traefik|nomad|consul' | cut -d, -f1,2,18
```

Expected: All 3 servers per backend show `UP` status.

**Step 4: Commit any fixes, update progress doc**

---

### Task 6: Document SSH tunnel configuration

**Step 1: Add SSH tunnel info to progress doc**

After testing is verified, append SSH tunnel configuration to `docs/plans/2026-02-21-vm-deployment-progress.md` in the Current State section.

The user's SSH config additions for their hypervisor host entry:

```
LocalForward 8443 localhost:443
LocalForward 4646 localhost:4646
LocalForward 8500 localhost:8500
```

Then access services via:
- `https://localhost:8443` - Traefik / all web services
- `http://localhost:4646` - Nomad UI
- `http://localhost:8500` - Consul UI

**Step 2: Final commit**

```bash
git add docs/plans/2026-02-21-vm-deployment-progress.md
git commit -m "docs: add HAProxy and SSH tunnel info to progress tracker"
```
