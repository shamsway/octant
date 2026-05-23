# App Migration & Rebrand Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate 25 apps from octant-private, rebrand homelab->octant, add DNS tier support, create 1Password seeding role, and validate with full rebuild.

**Architecture:** Terraform modules deploy Nomad jobs via the apply-terraform Ansible role. Each module follows a standardized pattern: empty 1Password provider (SaaS auth), configurable vault name, localhost defaults for nomad/consul. The apply-terraform role iterates terraform_execution_order, running `terraform apply` for each module against the cluster API.

**Tech Stack:** Ansible, Terraform, Nomad HCL, 1Password CLI, Consul, Podman, CephFS

---

### Task 1: Rebrand - Rename homelab.yml to octant.yml

**Files:**
- Rename: `homelab.yml` -> `octant.yml`
- Modify: `playbooks/site.yml:23`
- Modify: `Makefile:33-45,63,117`
- Modify: `playbooks/01-provision-vms.yml:131`
- Modify: `playbooks/02-deploy-ceph.yml:10`
- Modify: `playbooks/03-deploy-services.yml:10`

**Step 1: Rename the playbook file**

```bash
cd /home/melliott/git/octant/.worktrees/vm-deployment
git mv homelab.yml octant.yml
```

**Step 2: Update the play name inside octant.yml**

Change line 2 from:
```yaml
- name: Beginning Homelab Deploy
```
to:
```yaml
- name: Beginning Octant Deploy
```

**Step 3: Update playbooks/site.yml**

Change line 11 comment and line 23 import:
```yaml
#   octant - Configure Consul/Nomad/Podman cluster
```
```yaml
  ansible.builtin.import_playbook: ../octant.yml
```

**Step 4: Update Makefile**

Replace all `homelab.yml` references with `octant.yml` in the following targets: `deploy`, `deploy-verbose`, `deploy-host`, `deploy-role`, `deploy-role-host`, `run-flush-cache`, `deploy-cluster`.

**Step 5: Update playbook comments**

- `playbooks/01-provision-vms.yml:131` - update debug message: `Next step: ansible-playbook octant.yml`
- `playbooks/02-deploy-ceph.yml:10` - update comment: `#   - octant.yml has been run`
- `playbooks/03-deploy-services.yml:10` - update comment: `#   - Cluster configured with octant.yml`

**Step 6: Commit**

```bash
git add -A
git commit -m "refactor: rename homelab.yml to octant.yml

Rebrand the main cluster playbook from homelab to octant.
Updates all references in Makefile, site.yml, and playbook comments."
```

---

### Task 2: Rebrand - Change /opt/homelab/ to /opt/octant/

**Files:**
- Modify: `inventory/group_vars/all.yml:3-4,7-13,16-21`
- Modify: `reset-server.yml:14-16`
- Modify: `roles/restic/templates/restic-backup.sh.j2:19`
- Modify: `roles/vm_provision/defaults/main.yml:12`

**Step 1: Update group_vars/all.yml**

Replace all `/opt/homelab/` with `/opt/octant/`:
```yaml
configdir: /opt/octant/config
datadir: /opt/octant/data

configdirs:
  consul-server: "/opt/octant/config/consul-server.d"
  nomad-server: "/opt/octant/config/nomad-server.d"
  consul-agent: "/opt/octant/config/consul-agent.d"
  nomad-agent: "/opt/octant/config/nomad-agent.d"
  consul-agent-root: "/opt/octant/config/consul-agent-root.d"
  nomad-agent-root: "/opt/octant/config/nomad-agent-root.d"
  tls: "/opt/octant/config/tls"

datadirs:
  consul-server: "/opt/octant/data/consul-server"
  nomad-server: "/opt/octant/data/nomad-server"
  consul-agent: "/opt/octant/data/consul-agent"
  nomad-agent: "/opt/octant/data/nomad-agent"
  consul-agent-root: "/opt/octant/data/consul-agent-root"
  nomad-agent-root: "/opt/octant/data/nomad-agent-root"
```

**Step 2: Update reset-server.yml**

Change path from `/opt/homelab` to `/opt/octant`.

**Step 3: Update restic backup template**

Change `/opt/homelab` to `/opt/octant` in `roles/restic/templates/restic-backup.sh.j2`.

**Step 4: Update vm_provision defaults comment**

Change comment in `roles/vm_provision/defaults/main.yml:12` from "targets homelab.yml" to "targets octant.yml".

**Step 5: Commit**

```bash
git add inventory/group_vars/all.yml reset-server.yml roles/restic/templates/restic-backup.sh.j2 roles/vm_provision/defaults/main.yml
git commit -m "refactor: change /opt/homelab/ paths to /opt/octant/

Updates all config and data directory paths from /opt/homelab/ to
/opt/octant/ as part of the octant rebrand."
```

---

### Task 3: Rebrand - Update documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/ansible/README.md`
- Modify: `docs/baremetal/README.md`
- Modify: `docs/ceph/README.md`
- Modify: `docs/podman/README.md`
- Modify: `scripts/generate-secrets.sh:87`
- Modify: `docs/plans/2026-02-21-vm-deployment-design.md`
- Modify: `docs/plans/2026-02-21-vm-deployment-implementation.md`
- Modify: `docs/plans/2026-02-21-vm-deployment-progress.md`

**Step 1: Update README.md**

- Change `homelab.yml` references to `octant.yml`
- Change "An opinionated home lab framework" to "An opinionated lab framework"
- Change "home lab" to "lab" in prose (FAQ section, description, etc.)
- Keep external link to `hashi-homelab` unchanged (it's a different project)

**Step 2: Update docs/**

In each doc file, replace:
- `homelab.yml` -> `octant.yml`
- `/opt/homelab/` -> `/opt/octant/`
- "home lab" -> "lab" (in prose)
- "homelab framework" -> "Octant framework"

**Step 3: Update generate-secrets.sh**

Change line 87 reference from `homelab.yml` to `octant.yml`.

**Step 4: Update plan docs**

Update design/implementation/progress docs with the same replacements. These are historical records so use judgment - update references that would be confusing if left as-is, but leave bug fix history entries unchanged since they reference specific commits.

**Step 5: Commit**

```bash
git add README.md docs/ scripts/generate-secrets.sh
git commit -m "docs: complete homelab->octant rebrand in documentation

Updates all documentation references from homelab to octant,
including README, ansible docs, baremetal docs, and plan docs."
```

---

### Task 4: DNS Tier Support - Update defaults and Traefik config

**Files:**
- Modify: `inventory/group_vars/all.yml`
- Modify: `terraform/traefik/variables.tf`
- Modify: `terraform/traefik/traefik.toml`
- Modify: `terraform/postgres/variables.tf`
- Modify: `terraform/litellm/variables.tf`
- Create: `docs/dns-setup.md`

**Step 1: Add domain/DNS tier variables to group_vars/all.yml**

Add after the `dns2` line:
```yaml
# Service domain for Traefik routing
# Tier 1 (default): sslip.io-based, zero config, HTTP only
# Tier 2 (opt-in): Real domain with Cloudflare DNS-01 for HTTPS
# Example: lab.octant.net, lab.shamsway.net
service_domain: "192-168-122-101.sslip.io"
service_certresolver: ""  # Set to "cloudflare" for Tier 2 DNS
```

**Step 2: Update terraform variable defaults**

In `terraform/traefik/variables.tf`, `terraform/postgres/variables.tf`, and `terraform/litellm/variables.tf`, update:
```hcl
variable "domain" {
  type    = string
  default = "octant.local"
}

variable "dns" {
  type    = list(string)
  default = ["192.168.122.1"]
}
```

Note: The actual domain value is passed by the apply-terraform role from group_vars. The defaults here are fallbacks only.

**Step 3: Update traefik.toml for conditional TLS**

Replace the `[certificatesResolvers.cloudflare.acme]` section - keep it as-is since it only activates when `certresolver` is set to `cloudflare`. Update the `defaultRule` in `[providers.consulcatalog]` to use `octant.net` pattern (this gets overridden by service tags anyway).

**Step 4: Update apply-terraform role to pass domain variables**

Modify `roles/apply-terraform/tasks/apply_module.yml` - add `service_domain` and `service_certresolver` to the tf_variables:
```yaml
- name: Build terraform variables for {{ terraform_module }}
  ansible.builtin.set_fact:
    tf_variables: >-
      {{ transformed_env_vars | combine({
        'nomad': cluster_address,
        'consul': cluster_address,
        'domain': service_domain | default('octant.local'),
        'certresolver': service_certresolver | default(''),
        'dns': dns1 | default('192.168.122.1'),
      }) }}
```

**Step 5: Create docs/dns-setup.md**

Document both tiers:
- Tier 1: sslip.io default, how it works, limitations (HTTP only)
- Tier 2: Cloudflare setup steps (create domain/subdomain, create API token, add to 1Password, set group_vars, wildcard A record)
- Example: `lab.octant.net` as the documented subdomain

**Step 6: Commit**

```bash
git add inventory/group_vars/all.yml terraform/traefik/variables.tf terraform/postgres/variables.tf terraform/litellm/variables.tf roles/apply-terraform/tasks/apply_module.yml docs/dns-setup.md
git commit -m "feat: add DNS tier support (sslip.io default + Cloudflare opt-in)

Tier 1: sslip.io-based domain for zero-config HTTP routing.
Tier 2: Real domain with Cloudflare DNS-01 for wildcard HTTPS.
Domain and certresolver variables flow from group_vars through
apply-terraform into each module."
```

---

### Task 5: Create 1Password Seeding Role

**Files:**
- Create: `roles/seed-onepassword/tasks/main.yml`
- Create: `roles/seed-onepassword/defaults/main.yml`
- Modify: `playbooks/03-deploy-services.yml`
- Modify: `Makefile`

**Step 1: Create role defaults**

Create `roles/seed-onepassword/defaults/main.yml`:
```yaml
---
op_vault_name: "Octant"

# Items to auto-seed with generated credentials
op_seed_items:
  - title: "Postgres"
    category: "login"
    username: "postgres"
    generate_password: true

  - title: "postgres_litellm"
    category: "login"
    username: "litellm"
    generate_password: true

  - title: "postgres_n8n"
    category: "login"
    username: "n8n"
    generate_password: true

  - title: "postgres_phoenix"
    category: "login"
    username: "phoenix"
    generate_password: true

  - title: "service_mariadb"
    category: "password"
    generate_password: true

  - title: "litellm"
    category: "login"
    username: "admin"
    generate_password: true

# Optional items - log a message if missing but don't create
op_optional_items:
  - title: "OpenAI API Key"
    used_by: "litellm"
  - title: "Anthropic API Key"
    used_by: "litellm"
  - title: "Replicate API Key"
    used_by: "litellm"
  - title: "Openrouter API Key"
    used_by: "litellm"
  - title: "Cohere API Key"
    used_by: "litellm"
  - title: "Groq API Key"
    used_by: "litellm"
  - title: "Langfuse API Key"
    used_by: "litellm"
  - title: "n8n.shamsway.net"
    used_by: "n8n"
  - title: "db_phoenix"
    used_by: "phoenix"
  - title: "api_anthropic_key"
    used_by: "openclaw-gateway"
  - title: "api_openclaw_discord"
    used_by: "openclaw-gateway"
  - title: "api_openclaw_slack_bot"
    used_by: "openclaw-gateway"
  - title: "api_openclaw_slack_app"
    used_by: "openclaw-gateway"
  - title: "api_sendgrid_key"
    used_by: "ntfy"
```

**Step 2: Create role tasks**

Create `roles/seed-onepassword/tasks/main.yml`:
```yaml
---
- name: Get vault ID
  ansible.builtin.command: op vault get "{{ op_vault_name }}" --format json
  register: vault_info
  changed_when: false

- name: Set vault UUID
  ansible.builtin.set_fact:
    op_vault_uuid: "{{ (vault_info.stdout | from_json).id }}"

- name: Check existing items
  ansible.builtin.command: op item list --vault "{{ op_vault_name }}" --format json
  register: existing_items_raw
  changed_when: false

- name: Parse existing item titles
  ansible.builtin.set_fact:
    existing_item_titles: "{{ (existing_items_raw.stdout | from_json) | map(attribute='title') | list }}"

- name: Seed missing items
  ansible.builtin.command: >
    op item create
    --vault "{{ op_vault_name }}"
    --category "{{ item.category }}"
    --title "{{ item.title }}"
    {% if item.username is defined %}--username "{{ item.username }}"{% endif %}
    --generate-password='32,letters,digits'
  loop: "{{ op_seed_items }}"
  when: item.title not in existing_item_titles
  register: seed_results

- name: Report seeded items
  ansible.builtin.debug:
    msg: "Created 1Password item: {{ item.item.title }}"
  loop: "{{ seed_results.results | default([]) }}"
  when: item.changed | default(false)

- name: Report skipped items (already exist)
  ansible.builtin.debug:
    msg: "1Password item already exists: {{ item.title }}"
  loop: "{{ op_seed_items }}"
  when: item.title in existing_item_titles

- name: Check optional items
  ansible.builtin.debug:
    msg: "Optional: '{{ item.title }}' not found in vault '{{ op_vault_name }}'. Create it manually to enable {{ item.used_by }}."
  loop: "{{ op_optional_items }}"
  when: item.title not in existing_item_titles
```

**Step 3: Add to deploy pipeline**

Add the role to `playbooks/03-deploy-services.yml` before the apply-terraform role:
```yaml
  roles:
    - role: seed-onepassword
    - role: apply-terraform
```

**Step 4: Add Makefile target**

Add to Makefile:
```makefile
seed-secrets:
	ansible-playbook playbooks/03-deploy-services.yml $(VM_CLUSTER_INVENTORY) --tags "seed-onepassword"
```

**Step 5: Tag the role**

Add tags to the role tasks file so it can run standalone.

**Step 6: Commit**

```bash
git add roles/seed-onepassword/ playbooks/03-deploy-services.yml Makefile
git commit -m "feat: add seed-onepassword role for automated credential creation

Creates missing 1Password items with generated passwords for core
services. Reports optional items that require manual creation for
apps with external API key dependencies."
```

---

### Task 6: Migrate Core Apps - Simple (no secrets, no config files)

**Files:**
- Create: `terraform/excalidraw/main.tf`
- Create: `terraform/excalidraw/variables.tf`
- Create: `terraform/excalidraw/excalidraw.nomad.hcl`
- Create: `terraform/mqtt/main.tf`
- Create: `terraform/mqtt/variables.tf`
- Create: `terraform/mqtt/mosquitto.nomad.hcl`
- Create: `terraform/nginx/main.tf`
- Create: `terraform/nginx/variables.tf`
- Create: `terraform/nginx/nginx.nomad.hcl`
- Create: `terraform/uptimekuma/main.tf`
- Create: `terraform/uptimekuma/variables.tf`
- Create: `terraform/uptimekuma/uptime-kuma.nomad.hcl`

**Pattern for each module (no secrets):**

`main.tf`:
```hcl
provider "nomad" {
  address = "http://${var.nomad}:4646"
}

resource "nomad_job" "SERVICE" {
  jobspec = templatefile("${path.module}/SERVICE.nomad.hcl", {
    region       = var.region
    datacenter   = var.datacenter
    image        = var.image
    domain       = var.domain
    certresolver = var.certresolver
    servicename  = var.servicename
    dns          = jsonencode(var.dns)
  })
}
```

`variables.tf` (standard set, update defaults per service):
```hcl
variable "nomad" {
  description = "Nomad server address"
  type        = string
  default     = "localhost"
}

variable "region" {
  type    = string
  default = "home"
}

variable "datacenter" {
  type    = string
  default = "octant"
}

variable "image" {
  type    = string
  default = "IMAGE"
}

variable "domain" {
  type    = string
  default = "octant.local"
}

variable "certresolver" {
  type    = string
  default = ""
}

variable "servicename" {
  type    = string
  default = "SERVICE"
}

variable "dns" {
  type    = list(string)
  default = ["192.168.122.1"]
}
```

**Step 1: Create excalidraw module**

Copy `excalidraw.nomad.hcl` from octant-private. Adapt:
- Templatize: `datacenters`, `dns`, `domain`, `certresolver`, `servicename`
- Fix `${meta.rootless}` -> `$${meta.rootless}` (Terraform escape)
- Replace hardcoded `Host(\`excalidraw.shamsway.net\`)` with `Host(\`${servicename}.${domain}\`)`
- Image: `docker.io/excalidraw/excalidraw:latest`

**Step 2: Create mqtt module**

Copy `mosquito.nomad.hcl` from octant-private as `mosquitto.nomad.hcl`. Adapt:
- Templatize all hardcoded values
- Fix dollar-sign escapes
- Image: `docker.io/eclipse-mosquitto:2.0.18`
- Note: mqtt uses static port 1883 and volume mounts at `/mnt/services/mosquitto/`

**Step 3: Create nginx module**

Copy `nginx.nomad.hcl` from octant-private. Adapt:
- Templatize all hardcoded values
- Replace `Host(\`web.shamsway.net\`)` with `Host(\`${servicename}.${domain}\`)`
- Image: `docker.io/nginxinc/nginx-unprivileged:1.25.4`
- Note: nginx uses host volume `nginx-data`

**Step 4: Create uptimekuma module**

Copy from octant-private. Adapt per standard pattern.
- Image: `docker.io/louislam/uptime-kuma:2.1.3`
- Note: uptimekuma references nomadVar `nomad/jobs/uptime-kuma` for MariaDB connection - for VM deployment, simplify to use SQLite (remove the template block referencing nomadVar, remove the mariadb env vars)

**Step 5: Commit**

```bash
git add terraform/excalidraw/ terraform/mqtt/ terraform/nginx/ terraform/uptimekuma/
git commit -m "feat: add excalidraw, mqtt, nginx, uptimekuma terraform modules

New full terraform modules created from octant-private nomad job specs.
All adapted to VM deployment patterns (localhost defaults, octant datacenter)."
```

---

### Task 7: Migrate Core Apps - With 1Password (mariadb, pgadmin)

**Files:**
- Create: `terraform/mariadb/main.tf`
- Create: `terraform/mariadb/variables.tf`
- Create: `terraform/mariadb/mariadb.nomad.hcl`
- Create: `terraform/pgadmin/main.tf`
- Create: `terraform/pgadmin/variables.tf`
- Create: `terraform/pgadmin/pgadmin.nomad.hcl`

**Step 1: Create mariadb module**

Copy from octant-private. Adapt:
- Remove `backend "consul"` block
- Remove `required_providers` for nomad (not needed without backend)
- Change 1Password provider from CLI-based to empty block (SaaS auth)
- Change vault from `"Dev"` to `var.op_vault_name`
- Change nomad default from `"nomad.service.consul"` to `"localhost"`
- Change datacenter from `"shamsway"` to `"octant"`
- Change dns defaults to `["192.168.122.1"]`
- Add `op_vault_name`, `consul`, `domain`, `certresolver` variables
- Nomad job: templatize hardcoded values, remove `affinity` block (no physical/virtual distinction in VM env)

**Step 2: Create pgadmin module**

Copy from octant-private. Adapt:
- Remove `backend "consul"` block
- Change from OP_API_TOKEN/Connect-based auth to empty provider block
- Change vault from `"Dev"` to `var.op_vault_name`
- Remove `OP_API_TOKEN` variable, add `op_vault_name` variable
- Change defaults (nomad, datacenter, dns, domain, shared_dir)
- Change `shared_dir` default from `/opt/storage/` to `/mnt/services/`
- Nomad job: templatize dns servers (currently hardcoded), fix email from `pgadmin@shamsway.net` to use variable
- Change `pgadmin_email` default to `pgadmin@octant.local`
- Note: pgadmin runs as rootful (`meta.rootless = false`), needs root nomad agent

**Step 3: Commit**

```bash
git add terraform/mariadb/ terraform/pgadmin/
git commit -m "feat: add mariadb, pgadmin terraform modules

Adapted from octant-private with standardized 1Password SaaS auth,
configurable vault name, and VM deployment defaults."
```

---

### Task 8: Migrate Core Apps - With config files (qdrant, searxng, homepage)

**Files:**
- Create: `terraform/qdrant/` (main.tf, variables.tf, qdrant.nomad.hcl)
- Create: `terraform/searxng/` (main.tf, variables.tf, searxng.nomad.hcl)
- Create: `terraform/homepage/` (main.tf, variables.tf, homepage.nomad.hcl)

**Step 1: Create qdrant module**

Copy from octant-private. Adapt per standard pattern.
- Remove `backend "consul"` and `required_providers` blocks
- Change defaults (nomad->localhost, datacenter->octant, dns, domain)
- Add `consul` variable, change defaults
- Nomad job: fix `logging { }` syntax to `logging = { }` (HCL syntax)
- Image: `docker.io/qdrant/qdrant:v1.12.5-unprivileged`

**Step 2: Create searxng module**

Copy from octant-private. Adapt:
- Remove `backend "consul"` and `required_providers` blocks (onepassword not actually used)
- Change defaults
- Nomad job: templatize dns (currently uses join interpolation - keep that pattern)
- Note: searxng includes a redis sidecar task
- Note: searxng needs `cap_add` capabilities - verify these work with rootless podman

**Step 3: Create homepage module**

Copy from octant-private. Adapt:
- Remove `backend "consul"` block
- Remove `OP_API_TOKEN` and `op_vault` variables (not used in main.tf)
- Change defaults
- Nomad job: replace hardcoded `certresolver=cloudflare` in tags with `${certresolver}` variable

**Step 4: Commit**

```bash
git add terraform/qdrant/ terraform/searxng/ terraform/homepage/
git commit -m "feat: add qdrant, searxng, homepage terraform modules

Qdrant vector DB, SearXNG meta search (with redis sidecar), and
Homepage dashboard. All adapted for VM deployment."
```

---

### Task 9: Migrate Observability Stack

**Files:**
- Create: `terraform/prometheus/` (main.tf, variables.tf, prometheus.nomad.hcl)
- Create: `terraform/loki/` (main.tf, variables.tf, loki.nomad.hcl)
- Create: `terraform/tempo/` (main.tf, variables.tf, tempo.nomad.hcl)
- Create: `terraform/alertmanager/` (main.tf, variables.tf, alertmanager.nomad.hcl, alertmanager.yml)
- Create: `terraform/alloy/` (main.tf, variables.tf, alloy.nomad.hcl, config.alloy)
- Create: `terraform/grafana/` (main.tf, variables.tf, grafana.nomad.hcl, grafana-datasources.yml)
- Create: `terraform/gatus/` (main.tf, variables.tf, gatus.nomad.hcl, config.yaml)

**Step 1: Create prometheus module**

Copy from octant-private. Adapt:
- Remove `backend "consul"` block
- Change defaults (nomad->localhost, datacenter->octant)
- Add missing standard variables (domain, certresolver, servicename, dns, consul)
- Pass domain/certresolver/servicename/dns to job template
- Nomad job: IMPORTANT - templatize all hardcoded `shamsway.net` and `consul.shamsway.net:8500` references
  - Replace `consul.shamsway.net:8500` with `consul.service.consul:8500` (internal Consul address)
  - Replace all `shamsway.net` host rules with `${servicename}.${domain}`
  - Templatize dns servers
  - Keep the prometheus config template (scrape configs, alerting rules) but update consul addresses

**Step 2: Create loki module**

Copy from octant-private. Adapt per standard pattern.
- Add missing standard variables (domain, certresolver, servicename, dns)
- Nomad job: templatize hardcoded `loki.shamsway.net` and dns servers

**Step 3: Create tempo module**

Copy from octant-private. Already uses variables well.
- Remove `backend "consul"` block
- Change defaults

**Step 4: Create alertmanager module**

Copy from octant-private including `alertmanager.yml`.
- Remove `backend "consul"` block
- Change defaults
- `alertmanager.yml`: update webhook URL from `openclaw.service.consul` to be generic (or keep as-is - it's a config file the user can edit)

**Step 5: Create alloy module**

Copy from octant-private including `config.alloy`.
- Remove `backend "consul"` block
- Change defaults
- `config.alloy`: references `loki.service.consul:3100` and `prometheus.service.consul:9091` - these are internal Consul addresses and correct for the VM env
- Note: alloy is a `type = "system"` job (runs on every node)

**Step 6: Create grafana module**

Copy from octant-private including `grafana-datasources.yml`.
- Remove `backend "consul"` block
- Change defaults
- Add missing standard variables (domain, certresolver, servicename, dns)
- Pass them to job template
- Nomad job: templatize hardcoded `grafana.shamsway.net` and dns servers
- `grafana-datasources.yml`: references `prometheus.service.consul:9091`, `loki.service.consul:3100`, `tempo.service.consul:3200` - these are correct internal addresses

**Step 7: Create gatus module**

Copy from octant-private including `config.yaml`.
- Remove `backend "consul"` block
- Change defaults
- `config.yaml`: update `uptimekuma.shamsway.net` references and SSL check URLs to use the correct domain (or remove SSL checks for now since Tier 1 is HTTP-only)
- Keep internal consul service URLs as-is (`grafana.service.consul:3000`, etc.)

**Step 8: Commit**

```bash
git add terraform/prometheus/ terraform/loki/ terraform/tempo/ terraform/alertmanager/ terraform/alloy/ terraform/grafana/ terraform/gatus/
git commit -m "feat: add observability stack (prometheus, loki, tempo, alertmanager, alloy, grafana, gatus)

Complete monitoring and observability stack adapted for VM deployment.
Grafana pre-configured with Prometheus, Loki, and Tempo datasources.
All internal service discovery via Consul DNS."
```

---

### Task 10: Migrate Optional Apps (n8n, open-webui, phoenix, openclaw-gateway, ntfy)

**Files:**
- Create: `terraform/n8n/` (main.tf, variables.tf, n8n.nomad.hcl)
- Create: `terraform/open-webui/` (main.tf, variables.tf, open-webui.nomad.hcl)
- Create: `terraform/phoenix/` (main.tf, variables.tf, phoenix.nomad.hcl)
- Create: `terraform/openclaw-gateway/` (main.tf, variables.tf, openclaw-gateway.nomad.hcl)
- Create: `terraform/ntfy/` (main.tf, variables.tf, ntfy.nomad.hcl)

**Step 1: Create n8n module**

Copy from octant-private. Major adaptations:
- Remove ALL Cloudflare resources (provider, tunnel, access app, policy, CNAME)
- Remove `cloudflare` from `required_providers`
- Change 1Password from `service_account_token = var.OP_SERVICE_ACCOUNT_TOKEN` to empty provider block
- Remove `OP_SERVICE_ACCOUNT_TOKEN` variable, add `op_vault_name`
- Change vault from `"Dev"` to `var.op_vault_name`
- Remove `cloudflared_image` variable and the `ha_n8n` (cloudflared sidecar) task from nomad job
- Remove `tunnel_n8n` from template variables
- Change defaults (nomad, datacenter, dns, domain, n8n_public_url)
- Remove `backend "consul"` block

**Step 2: Create open-webui module**

Copy from octant-private. Adapt:
- Change from OP_API_TOKEN/Connect-based auth to empty provider block
- Remove `OP_API_TOKEN` variable, add `op_vault_name`
- Change vault from `"Dev"` to `var.op_vault_name`
- Remove `backend "consul"` block
- Change defaults
- Update `webui_url` default from `https://chatllm.shamsway.net` to match domain pattern
- Nomad job: update hardcoded `chatllm.${domain}` in Host rule to `${servicename}.${domain}`

**Step 3: Create phoenix module**

Copy from octant-private. Adapt:
- Change from `service_account_token = var.OP_SERVICE_ACCOUNT_TOKEN` to empty provider block
- Remove `OP_SERVICE_ACCOUNT_TOKEN` variable, add `op_vault_name`
- Change vault from `"Dev"` to `var.op_vault_name`
- Remove `backend "consul"` block and `required_providers` for nomad
- Change defaults

**Step 4: Create openclaw-gateway module**

Copy from octant-private. Adapt:
- Change from CLI-based 1Password to empty provider block
- Change vault from `"Dev"` to `var.op_vault_name`
- Add `op_vault_name` variable
- Remove `backend "consul"` block
- Change defaults
- Nomad job: remove node constraint (`node.unique.name = jerry-agent` is production-specific)
- Change image default from registry-based to a public image or placeholder

**Step 5: Create ntfy module**

Copy from octant-private. Major adaptations:
- Remove ALL Cloudflare resources (provider, tunnel, access app, policy, CNAME)
- Remove `cloudflare` from `required_providers`
- Change 1Password from SA token to empty provider block
- Remove `OP_SERVICE_ACCOUNT_TOKEN` variable, add `op_vault_name`
- Change vault from `"Dev"` to `var.op_vault_name`
- Remove `backend "consul"` block
- Remove `cloudflared_image` variable and `ha_ntfy` (cloudflared sidecar) task
- Remove `tunnel_ntfy` from template variables
- Change SMTP config to use variables instead of direct 1Password references (SMTP is optional)
- Change defaults

**Step 6: Commit**

```bash
git add terraform/n8n/ terraform/open-webui/ terraform/phoenix/ terraform/openclaw-gateway/ terraform/ntfy/
git commit -m "feat: add optional apps (n8n, open-webui, phoenix, openclaw-gateway, ntfy)

Optional apps that require external API keys or configuration.
Cloudflare tunnels stripped - all route through Traefik.
Will fail gracefully during terraform apply if required 1Password
items are missing."
```

---

### Task 11: Update Execution Order and Apply-Terraform Defaults

**Files:**
- Modify: `roles/apply-terraform/defaults/main.yml`
- Modify: `inventory/group_vars/all.yml` (terraform_execution_order)

**Step 1: Update apply-terraform defaults**

Add new module env patterns for modules that need them. Update the commented-out execution order.

**Step 2: Update terraform_execution_order in group_vars/all.yml**

Replace the current order with the full list:
```yaml
terraform_execution_order:
  # Core infrastructure
  - traefik
  - postgres
  - registry
  - mariadb
  - nginx
  - mqtt
  - excalidraw
  - qdrant
  - searxng
  - uptimekuma
  - pgadmin
  - homepage
  # Observability stack
  - prometheus
  - loki
  - tempo
  - alertmanager
  - alloy
  - grafana
  - gatus
  # LLM stack
  - litellm
  # Optional (require external config - will fail if 1Password items missing)
  # Uncomment as needed:
  # - n8n
  # - open-webui
  # - phoenix
  # - openclaw-gateway
  # - ntfy
```

Note: Optional apps are commented out by default so they don't break the deploy pipeline.

**Step 3: Update apply-terraform defaults/main.yml**

Add new modules to `terraform_module_env_patterns`:
```yaml
terraform_module_env_patterns:
  traefik:
    - cloudflare_username
    - cloudflare_api_key
  postgres: []
  litellm: []
  registry:
    - registry_admin_password
  mariadb: []
  nginx: []
  mqtt: []
  excalidraw: []
  pgadmin: []
  qdrant: []
  searxng: []
  uptimekuma: []
  homepage: []
  prometheus: []
  loki: []
  tempo: []
  alertmanager: []
  alloy: []
  grafana: []
  gatus: []
  n8n: []
  open-webui: []
  phoenix: []
  openclaw-gateway: []
  ntfy: []
```

**Step 4: Commit**

```bash
git add roles/apply-terraform/defaults/main.yml inventory/group_vars/all.yml
git commit -m "feat: update terraform execution order with all migrated apps

Core and observability apps enabled by default. Optional apps
commented out - uncomment after configuring required 1Password items."
```

---

### Task 12: Update Volumes for New Services

**Files:**
- Modify: `inventory/group_vars/all.yml` or equivalent volumes config
- Modify: `playbooks/02-deploy-ceph.yml` (if volume dirs are created there)

**Step 1: Identify volume directories needed**

Services that use CephFS-mounted volumes at `/mnt/services/`:
```
/mnt/services/mariadb/data
/mnt/services/mosquitto/config
/mnt/services/mosquitto/data
/mnt/services/mosquitto/log
/mnt/services/grafana/data
/mnt/services/grafana/config
/mnt/services/prometheus
/mnt/services/loki
/mnt/services/tempo
/mnt/services/alertmanager/data
/mnt/services/gatus/data
/mnt/services/uptimekuma/data
/mnt/services/searxng/config
/mnt/services/searxng/data
/mnt/services/homepage/config
/mnt/services/n8n/config
/mnt/services/n8n/data
/mnt/services/open-webui/data
/mnt/services/phoenix/data
/mnt/services/openclaw-gateway/config
/mnt/services/ntfy/config
/mnt/services/ntfy/data
/mnt/services/qdrant/data
```

Services that use Nomad host volumes (defined in nomad agent config):
```
nginx-data -> /mnt/services/nginx/data
```

**Step 2: Add volume directories to the post-Ceph creation task**

Check `playbooks/02-deploy-ceph.yml` post_tasks or the volumes role for where directories are created on CephFS. Add the new service directories.

**Step 3: Add Nomad host volume definitions if needed**

Check nomad agent config templates for host_volume definitions. Add `nginx-data` if nginx uses a host volume.

**Step 4: Commit**

```bash
git add playbooks/02-deploy-ceph.yml inventory/
git commit -m "feat: add CephFS volume directories for new services

Creates required /mnt/services/ subdirectories for all migrated
services after CephFS mount."
```

---

### Task 13: Update Health Check Playbook

**Files:**
- Modify: `playbooks/04-health-check.yml`

**Step 1: Add service health checks**

Add checks for key deployed services after the existing infrastructure checks:
```yaml
    - name: Check Traefik is registered in Consul
      ansible.builtin.uri:
        url: "http://localhost:8500/v1/catalog/service/traefik"
        return_content: true
      register: traefik_check
      failed_when: traefik_check.json | length == 0
      when: inventory_hostname == groups['servers'][0]

    - name: Check Postgres is registered in Consul
      ansible.builtin.uri:
        url: "http://localhost:8500/v1/catalog/service/postgres"
        return_content: true
      register: postgres_check
      failed_when: postgres_check.json | length == 0
      when: inventory_hostname == groups['servers'][0]

    - name: List all Nomad jobs
      ansible.builtin.shell: nomad job status
      register: nomad_jobs
      changed_when: false
      when: inventory_hostname == groups['servers'][0]
      environment:
        NOMAD_ADDR: "http://localhost:4646"

    - name: Display Nomad jobs
      ansible.builtin.debug:
        var: nomad_jobs.stdout_lines
      when: inventory_hostname == groups['servers'][0]
```

**Step 2: Commit**

```bash
git add playbooks/04-health-check.yml
git commit -m "feat: add service health checks to health-check playbook

Verifies key services are registered in Consul and lists all
Nomad jobs as part of cluster health validation."
```

---

### Task 14: Test Deployment

**Step 1: Seed 1Password items**

```bash
make seed-secrets
```

Verify output shows items created or skipped.

**Step 2: Deploy services**

```bash
make deploy-services
```

Watch for terraform errors. Core apps should all succeed. Optional apps (if commented out) won't run.

**Step 3: Verify services in Nomad**

```bash
ssh admin@192.168.122.101 'NOMAD_ADDR=http://localhost:4646 nomad job status'
```

All core jobs should show status "running".

**Step 4: Verify services in Consul**

```bash
ssh admin@192.168.122.101 'consul catalog services'
```

All services should be listed.

**Step 5: Run health check**

```bash
make health-check
```

**Step 6: Commit any fixes**

```bash
git add -A
git commit -m "fix: deployment fixes from testing"
```

---

### Task 15: Full Rebuild Validation

**Step 1: Full teardown and rebuild**

```bash
make rebuild
```

This runs `teardown-force` then `deploy-vm` (base image -> provision -> cluster -> ceph -> services -> health check).

**Step 2: Verify end-to-end success**

- All VMs provisioned
- Consul/Nomad cluster healthy
- Ceph HEALTH_OK
- All core services deployed and registered
- Health check passes

**Step 3: Test Tier 2 DNS (if configured)**

If `lab.shamsway.net` is configured:
- Verify Cloudflare wildcard record exists
- Verify Traefik obtains Let's Encrypt cert
- Verify `grafana.lab.shamsway.net` resolves and serves HTTPS

**Step 4: Commit final state**

```bash
git add -A
git commit -m "test: validated full rebuild with all migrated services"
```

---

### Task 16: Update Progress Tracker and Design Docs

**Files:**
- Modify: `docs/plans/2026-02-21-vm-deployment-progress.md`

**Step 1: Update progress tracker**

Update the "Remaining Work" section and phase status table to reflect:
- App migration complete
- Full rebuild validated
- Branch ready for merge review

**Step 2: Commit**

```bash
git add docs/plans/
git commit -m "docs: update progress tracker with migration completion status"
```
