# BastionClaw

**Description:** Personal AI assistant with OS-level container isolation for agent execution. Deploys as a Nomad service using Podman-out-of-Podman via socket mount. Semantic memory (qmd) runs inline in the orchestrator process.

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

Build and push from the BastionClaw source (see `local/bastionclaw/`).

Before building, ensure `src/container-runner.ts` includes `ANTHROPIC_BASE_URL` and `ANTHROPIC_MODEL` in `allowedVars` and the `process.env` fallback.

```sh
# Agent image (from bastionclaw source)
cd local/bastionclaw
docker build -t 192.168.122.1:5000/bastionclaw-agent:latest -f container/Dockerfile container/
docker push 192.168.122.1:5000/bastionclaw-agent:latest

# Orchestrator image (must build TypeScript and UI first)
npm run build
npm run build:ui
docker build -t 192.168.122.1:5000/bastionclaw:latest -f ../../terraform/bastionclaw/Dockerfile.orchestrator .
docker push 192.168.122.1:5000/bastionclaw:latest
```

**Notes:**
- The hypervisor's Docker daemon must have `192.168.122.1:5000` in `insecure-registries` (see `/etc/docker/daemon.json`).
- `TELEGRAM_ONLY=true` is set to skip WhatsApp authentication. The WebUI channel is always available regardless of messaging channel config.
- The qmd sidecar was removed because qmd v1.0.7 has no `serve` command. The orchestrator runs qmd inline for indexing and search.
