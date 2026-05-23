# container-runner.ts Patch: Nomad/Podman-out-of-Podman Support

**Status**: Deferred — falling back to OpenClaw for now
**Date**: 2026-03-02

## The Core Problem

`buildVolumeMounts()` in `src/container-runner.ts` generates `hostPath` values using `process.cwd()` (= `/app` inside the orchestrator container). These paths are passed to `docker run -v` which goes through the Podman socket to the **host**, where `/app` doesn't exist. The error:

```
making volume mountpoint for volume /app/data/sessions/main/.claude: mkdir /app: permission denied
```

## What Needs Remapping

There are 6 mount sources that reference container-internal paths:

| Mount | Container Path (current) | Host Path (needed) |
|-------|-------------------------|-------------------|
| Project root (main only) | `/app` | Skip or map to CephFS |
| `.env` shadow | `/app/.env` | Skip — no `.env` in Nomad |
| Group folder | `/app/groups/<name>` | `/mnt/services/bastionclaw/groups/<name>` |
| Sessions dir | `/app/data/sessions/<name>/.claude` | `/mnt/services/bastionclaw/data/sessions/<name>/.claude` |
| IPC dir | `/app/data/ipc/<name>` | `/mnt/services/bastionclaw/data/ipc/<name>` |
| Agent-runner src | `/app/container/agent-runner/src` | Skip — already baked into agent image |

## Cleanest Approach

Add a single env var `CONTAINER_HOST_PATH_PREFIX` (e.g., `/mnt/services/bastionclaw`). When set, replace `/app/groups` with `$PREFIX/groups`, `/app/data` with `$PREFIX/data` in all `hostPath` values. Skip mounts that don't exist on the host (project root, .env shadow, agent-runner src).

Approximately 30-40 lines of code change in `buildVolumeMounts()`, one new env var in the Nomad job.

## Scope Estimate

- **Path translation layer**: ~2-4 hours (mechanical, small)
- **Mount skipping logic**: ~1-2 hours (skip project root, .env, agent-runner when in remote mode)
- **Testing**: ~2-3 hours (need full Nomad stack to validate each mount)
- **Total**: ~1 day focused work

## Other Issues Fixed During Deployment

These are resolved and would carry forward if bastionclaw is redeployed:

1. **Registry**: Use `192.168.122.1:5000` not `registry.service.consul:8082` (doesn't exist)
2. **Insecure registry**: Add to `/etc/docker/daemon.json` on hypervisor and `/etc/containers/registries.conf.d/local-registry.conf` on cluster nodes
3. **Docker CLI**: Use real Docker CLI static binary, not `podman-docker` (overlay-on-overlay fails)
4. **WhatsApp auth**: Set `TELEGRAM_ONLY=true` to skip
5. **qmd sidecar**: Remove — v1.0.7 has no `serve` command
6. **Main group bootstrap**: Insert into SQLite DB and create `groups/main/` folder
7. **LiteLLM port**: Must be static (4000) for `litellm.service.consul:4000` to work
8. **Agent image pre-pull**: Must pre-pull on cluster nodes via `sudo -u hashi podman pull`
