# BastionClaw Deployment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy BastionClaw on Octant via Nomad using Podman-out-of-Podman socket mount, backed by LiteLLM and the local glm-5-fp8 model.

**Architecture:** Nomad Podman task mounts the host's rootless Podman socket, allowing BastionClaw's orchestrator to spawn sibling agent containers. A qmd sidecar provides semantic memory. Traefik routes `bastionclaw.lab.shamsway.net` via Consul service discovery.

**Tech Stack:** Terraform, Nomad, Podman, Node.js 22, TypeScript, 1Password, Consul, Traefik

**Design doc:** `docs/plans/2026-02-27-bastionclaw-deployment-design.md`

---

### Task 1: Add host volumes to inventory

**Files:**
- Modify: `inventory/groups.yml` (after line ~197, after openclaw-gateway-workspaces)

**Step 1: Add bastionclaw volume entries**

Add the following entries to the `volumes` list under `servers.vars`:

```yaml
      - name: bastionclaw-groups
        path: /mnt/services/bastionclaw/groups
        backup: true
      - name: bastionclaw-store
        path: /mnt/services/bastionclaw/store
        backup: true
      - name: bastionclaw-data
        path: /mnt/services/bastionclaw/data
        backup: true
      - name: bastionclaw-qmd-models
        path: /mnt/services/bastionclaw/qmd-models
        backup: false
```

**Step 2: Verify YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('inventory/groups.yml'))"`
Expected: No output (no errors)

**Step 3: Commit**

```bash
git add inventory/groups.yml
git commit -m "feat(bastionclaw): add host volumes to inventory"
```

---

### Task 2: Modify BastionClaw source — readSecrets and allowedVars

BastionClaw's `readSecrets()` reads secrets from a `.env` file, but in Nomad secrets are injected as environment variables. We need two changes:

1. Add `ANTHROPIC_BASE_URL` to the allowed vars list
2. Fall back to `process.env` when `.env` file doesn't exist

**Files:**
- Modify: `local/bastionclaw/src/container-runner.ts:209-236`

**Step 1: Modify readSecrets function**

Replace the existing `readSecrets()` function (lines 209-236) with:

```typescript
function readSecrets(): Record<string, string> {
  // SDK auth + API keys needed by agent Bash tool calls
  const allowedVars = ['CLAUDE_CODE_OAUTH_TOKEN', 'ANTHROPIC_API_KEY', 'TRANSCRIPT_API_KEY', 'GEMINI_API_KEY', 'ANTHROPIC_BASE_URL'];
  const secrets: Record<string, string> = {};

  const envFile = path.join(process.cwd(), '.env');
  if (fs.existsSync(envFile)) {
    const content = fs.readFileSync(envFile, 'utf-8');

    for (const line of content.split('\n')) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;
      const eqIdx = trimmed.indexOf('=');
      if (eqIdx === -1) continue;
      const key = trimmed.slice(0, eqIdx).trim();
      if (!allowedVars.includes(key)) continue;
      let value = trimmed.slice(eqIdx + 1).trim();
      if (
        (value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))
      ) {
        value = value.slice(1, -1);
      }
      if (value) secrets[key] = value;
    }
  }

  // Fall back to process.env for vars not found in .env (e.g. Nomad-injected secrets)
  for (const key of allowedVars) {
    if (!secrets[key] && process.env[key]) {
      secrets[key] = process.env[key];
    }
  }

  return secrets;
}
```

**Step 2: Verify TypeScript compiles**

Run: `cd local/bastionclaw && npx tsc --noEmit`
Expected: No errors

**Step 3: Commit**

```bash
cd local/bastionclaw
git add src/container-runner.ts
git commit -m "feat: add ANTHROPIC_BASE_URL to secrets allowlist, fallback to process.env"
```

---

### Task 3: Create orchestrator Dockerfile

**Files:**
- Create: `terraform/bastionclaw/Dockerfile.orchestrator`

**Step 1: Create the terraform/bastionclaw directory**

```bash
mkdir -p terraform/bastionclaw
```

**Step 2: Write Dockerfile.orchestrator**

```dockerfile
# BastionClaw Orchestrator for Nomad/Podman deployment
# Runs the Node.js host process with access to host Podman via socket mount
FROM node:22-slim

# Install podman-docker for Docker CLI compatibility
# BastionClaw calls 'docker' which podman-docker redirects to podman
RUN apt-get update && apt-get install -y \
    podman-docker \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy package files first for better layer caching
COPY package*.json ./
RUN npm ci --omit=dev

# Copy compiled output and container assets
COPY dist/ ./dist/
COPY container/ ./container/

# Copy UI build if present
COPY ui/dist/ ./ui/dist/

# Create required directories
RUN mkdir -p groups store data

EXPOSE 3100

CMD ["node", "dist/index.js"]
```

**Step 3: Commit**

```bash
git add terraform/bastionclaw/Dockerfile.orchestrator
git commit -m "feat(bastionclaw): add orchestrator Dockerfile for Nomad deployment"
```

---

### Task 4: Create Terraform variables.tf

**Files:**
- Create: `terraform/bastionclaw/variables.tf`

**Step 1: Write variables.tf**

Follow the pattern from `terraform/n8n/variables.tf` and `terraform/openclaw-gateway/variables.tf`:

```hcl
variable "op_vault_name" {
  description = "1Password vault name"
  type        = string
  default     = "Octant"
}

variable "nomad" {
  description = "Nomad server address"
  type        = string
  default     = "localhost"
}

variable "consul" {
  description = "Consul server address"
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
  description = "Orchestrator container image"
  type        = string
  default     = "registry.service.consul:8082/bastionclaw:latest"
}

variable "agent_image" {
  description = "Agent container image spawned by orchestrator"
  type        = string
  default     = "registry.service.consul:8082/bastionclaw-agent:latest"
}

variable "domain" {
  type    = string
  default = "lab.shamsway.net"
}

variable "certresolver" {
  type    = string
  default = ""
}

variable "servicename" {
  type    = string
  default = "bastionclaw"
}

variable "dns" {
  type    = list(string)
  default = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}

variable "litellm_base_url" {
  description = "LiteLLM proxy base URL"
  type        = string
  default     = "http://litellm.service.consul:4000"
}

variable "podman_socket_path" {
  description = "Host path to rootless Podman socket (hashi user UID 2000)"
  type        = string
  default     = "/run/user/2000/podman/podman.sock"
}
```

**Step 2: Verify HCL syntax**

Run: `cd terraform/bastionclaw && terraform fmt -check variables.tf`
Expected: No output (already formatted) or auto-formats

**Step 3: Commit**

```bash
git add terraform/bastionclaw/variables.tf
git commit -m "feat(bastionclaw): add Terraform variables"
```

---

### Task 5: Create Terraform main.tf

**Files:**
- Create: `terraform/bastionclaw/main.tf`

**Step 1: Write main.tf**

Follow the N8N pattern (modern `templatefile()`, `depends_on`):

```hcl
terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 2.1.2"
    }
  }
}

provider "nomad" {
  address = "http://${var.nomad}:4646"
}

provider "onepassword" {}

data "onepassword_vault" "vault" {
  name = var.op_vault_name
}

data "onepassword_item" "api_anthropic_key" {
  vault = data.onepassword_vault.vault.uuid
  title = "api_anthropic_key"
}

data "onepassword_item" "service_litellm" {
  vault = data.onepassword_vault.vault.uuid
  title = "service_litellm"
}

resource "nomad_variable" "bastionclaw_secrets" {
  path = "nomad/jobs/bastionclaw"
  items = {
    anthropic_api_key = data.onepassword_item.api_anthropic_key.password
    litellm_api_key   = data.onepassword_item.service_litellm.password
  }
}

resource "nomad_job" "bastionclaw" {
  jobspec = templatefile("${path.module}/bastionclaw.nomad.hcl", {
    region             = var.region
    datacenter         = var.datacenter
    image              = var.image
    agent_image        = var.agent_image
    domain             = var.domain
    certresolver       = var.certresolver
    servicename        = var.servicename
    dns                = jsonencode(var.dns)
    litellm_base_url   = var.litellm_base_url
    podman_socket_path = var.podman_socket_path
  })
  depends_on = [nomad_variable.bastionclaw_secrets]
}
```

**Step 2: Verify HCL syntax**

Run: `cd terraform/bastionclaw && terraform fmt -check main.tf`

**Step 3: Commit**

```bash
git add terraform/bastionclaw/main.tf
git commit -m "feat(bastionclaw): add Terraform main.tf with 1Password secrets"
```

---

### Task 6: Create Nomad job spec (bastionclaw.nomad.hcl)

**Files:**
- Create: `terraform/bastionclaw/bastionclaw.nomad.hcl`

**Step 1: Write the Nomad HCL template**

Follow the pattern from `terraform/n8n/n8n.nomad.hcl` and `terraform/openclaw-gateway/openclaw-gateway.nomad.hcl`:

```hcl
job "bastionclaw" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "true"
  }

  group "bastionclaw" {
    network {
      port "webui" {
        static = 3100
        to     = 3100
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      port     = "webui"

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${servicename}.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}.tls.certresolver=${certresolver}",
        "traefik.http.routers.${servicename}.middlewares=redirect-web-to-websecure@internal",
      ]

      check {
        name     = "alive"
        type     = "tcp"
        port     = "webui"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "orchestrator" {
      driver = "podman"

      config {
        image              = "${image}"
        ports              = ["webui"]
        image_pull_timeout = "15m"
        volumes = [
          "${podman_socket_path}:/run/podman/podman.sock",
          "/mnt/services/bastionclaw/groups:/app/groups",
          "/mnt/services/bastionclaw/store:/app/store",
          "/mnt/services/bastionclaw/data:/app/data",
        ]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "${servicename}"
            }
          ]
        }
      }

      env {
        DOCKER_HOST            = "unix:///run/podman/podman.sock"
        ANTHROPIC_BASE_URL     = "${litellm_base_url}"
        CONTAINER_IMAGE        = "${agent_image}"
        WEBUI_PORT             = "3100"
        WEBUI_HOST             = "0.0.0.0"
        MAX_CONCURRENT_CONTAINERS = "3"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{- with nomadVar "nomad/jobs/bastionclaw" -}}
ANTHROPIC_API_KEY="{{ .anthropic_api_key }}"
LITELLM_API_KEY="{{ .litellm_api_key }}"
{{- end -}}
EOT
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }

    task "qmd" {
      driver = "podman"

      config {
        image              = "${image}"
        image_pull_timeout = "15m"
        entrypoint         = ["npx", "qmd", "serve", "--port", "8181"]
        volumes = [
          "/mnt/services/bastionclaw/groups:/app/groups",
          "/mnt/services/bastionclaw/data:/app/data",
          "/mnt/services/bastionclaw/qmd-models:/home/node/.cache/qmd/models",
        ]
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "${servicename}-qmd"
            }
          ]
        }
      }

      resources {
        cpu    = 500
        memory = 768
      }

      lifecycle {
        hook    = "poststart"
        sidecar = true
      }
    }
  }
}
```

Key notes:
- `orchestrator` task mounts the Podman socket and sets `DOCKER_HOST` so BastionClaw calls the host's Podman
- `qmd` task runs as a sidecar with `lifecycle { hook = "poststart"; sidecar = true }`
- Secrets are injected via Nomad template, and the modified `readSecrets()` falls back to `process.env`
- TCP health check on port 3100 (BastionClaw's WebUI/Fastify server)

**Step 2: Verify HCL syntax**

Run: `cd terraform/bastionclaw && terraform fmt bastionclaw.nomad.hcl`

**Step 3: Commit**

```bash
git add terraform/bastionclaw/bastionclaw.nomad.hcl
git commit -m "feat(bastionclaw): add Nomad job spec with Podman socket mount and qmd sidecar"
```

---

### Task 7: Create README.md

**Files:**
- Create: `terraform/bastionclaw/README.md`

**Step 1: Write README following existing service READMEs**

```markdown
# BastionClaw

**Description:** Personal AI assistant with OS-level container isolation for agent execution. Deploys as a Nomad service using Podman-out-of-Podman via socket mount, with a qmd semantic memory sidecar.

**Use cases:**
- Personal AI assistant accessible via browser WebUI
- Sandboxed code execution and web browsing via agent containers
- Semantic memory across conversations via qmd

**Rootless container:** Yes

**Dependencies:**
- LiteLLM (`litellm.service.consul:4000`) for LLM routing
- Local glm-5-fp8 model on hypervisor (`192.168.122.1:8000`)
- Rootless Podman socket on hashi user (UID 2000)

**Usage:**

- Change default variables set in `variables.tf` or set appropriate environment variables.
- Initialize Terraform

```sh
terraform init
```

- Deploy job

```sh
terraform apply -auto-approve
```

**URL:** https://bastionclaw.lab.shamsway.net/

**Container images:**

Build and push from the BastionClaw source (see `local/bastionclaw/`):

```sh
# Agent image (from bastionclaw source)
cd local/bastionclaw
podman build -t registry.service.consul:8082/bastionclaw-agent:latest -f container/Dockerfile container/
podman push registry.service.consul:8082/bastionclaw-agent:latest

# Orchestrator image
npm run build
podman build -t registry.service.consul:8082/bastionclaw:latest -f ../../terraform/bastionclaw/Dockerfile.orchestrator .
podman push registry.service.consul:8082/bastionclaw:latest
```
```

**Step 2: Commit**

```bash
git add terraform/bastionclaw/README.md
git commit -m "docs(bastionclaw): add README with deployment instructions"
```

---

### Task 8: Initialize Terraform and validate

**Step 1: Run terraform init**

Run: `cd terraform/bastionclaw && terraform init`
Expected: "Terraform has been successfully initialized!"

**Step 2: Run terraform validate**

Run: `cd terraform/bastionclaw && terraform validate`
Expected: "Success! The configuration is valid."

**Step 3: Run terraform plan (dry run)**

Run: `cd terraform/bastionclaw && terraform plan`
Expected: Plan shows 2 resources to create (nomad_variable, nomad_job). May fail if 1Password token is not set — that's OK for validation, the plan structure is what matters.

**Step 4: Commit any format changes**

```bash
cd terraform/bastionclaw
terraform fmt
git add -A
git commit -m "chore(bastionclaw): terraform fmt and init"
```

---

### Task 9: Pre-seed agent configuration

Before deploying, the main agent's CLAUDE.md needs to exist on the host.

**Step 1: Create the groups/main directory and CLAUDE.md**

This is done on the Nomad client node (not in the repo). SSH to a server node and run as hashi user:

```bash
mkdir -p /mnt/services/bastionclaw/groups/main
cat > /mnt/services/bastionclaw/groups/main/CLAUDE.md << 'EOF'
# Agent

You are a general-purpose assistant running on the Octant homelab.
EOF
```

Also create the store and data directories:

```bash
mkdir -p /mnt/services/bastionclaw/store
mkdir -p /mnt/services/bastionclaw/data
mkdir -p /mnt/services/bastionclaw/qmd-models
```

Note: If host volumes are managed by Ansible (via the volumes role), running the playbook from Task 1 will create these directories automatically. The CLAUDE.md still needs to be seeded manually.

**Step 2: Verify directories exist**

```bash
ls -la /mnt/services/bastionclaw/
```
Expected: `groups/`, `store/`, `data/`, `qmd-models/` directories

---

### Task 10: Build and push container images

This is done from a machine with Podman access and network access to `registry.service.consul:8082`.

**Step 1: Build the agent image**

```bash
cd local/bastionclaw
podman build -t registry.service.consul:8082/bastionclaw-agent:latest -f container/Dockerfile container/
```
Expected: Build completes successfully

**Step 2: Push the agent image**

```bash
podman push registry.service.consul:8082/bastionclaw-agent:latest
```

**Step 3: Build the orchestrator source**

```bash
cd local/bastionclaw
npm ci
npm run build
npm run build:ui
```
Expected: TypeScript compiles, UI builds

**Step 4: Build the orchestrator image**

```bash
podman build -t registry.service.consul:8082/bastionclaw:latest -f ../../terraform/bastionclaw/Dockerfile.orchestrator .
```
Expected: Build completes successfully

**Step 5: Push the orchestrator image**

```bash
podman push registry.service.consul:8082/bastionclaw:latest
```

---

### Task 11: Deploy with Terraform

**Step 1: Ensure 1Password service account token is available**

```bash
export OP_SERVICE_ACCOUNT_TOKEN="<your-token>"
```

**Step 2: Deploy**

```bash
cd terraform/bastionclaw
terraform apply -auto-approve
```
Expected: 2 resources created (nomad_variable, nomad_job)

**Step 3: Verify Nomad job status**

```bash
nomad job status bastionclaw
```
Expected: Both `orchestrator` and `qmd` tasks show as "running"

---

### Task 12: Validate deployment

**Step 1: Check Consul service registration**

```bash
consul catalog services | grep bastionclaw
```
Expected: `bastionclaw` listed

**Step 2: Check Traefik routing**

```bash
curl -sk https://bastionclaw.lab.shamsway.net/ | head -20
```
Expected: HTML response from BastionClaw WebUI

**Step 3: Test agent container spawning**

Send a test message via the WebUI at `https://bastionclaw.lab.shamsway.net/`. Then check for agent containers on a Nomad client node:

```bash
# As hashi user on a Nomad client
podman ps | grep bastionclaw
```
Expected: A `bastionclaw-main-*` container running temporarily

**Step 4: Check LiteLLM received the request**

```bash
nomad alloc logs $(nomad job status litellm | grep running | awk '{print $1}') | tail -20
```
Expected: Log entries showing a request for `local/glm-5-fp8`

**Step 5: Final commit**

```bash
git add -A
git commit -m "feat(bastionclaw): complete deployment configuration"
```
