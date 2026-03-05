# Design: MCP Server Migration to Octant

## Overview

Migrate 4 FastMCP-based MCP servers from `octant-private/terraform/agent-farm/mcp-servers/` into `octant/terraform/` as independent, cleanly deployed services. Strip legacy Langfuse observability, create a minimal pip-installable shared library, upgrade to FastMCP 3.x, and deploy using the established vm-deployment Terraform patterns.

## Motivation

- The agent-farm ecosystem is retired. The MCP servers are the only living infrastructure still under `agent-farm/`.
- The `common/` library has ~90 files, most serving retired agents. Only ~15-20 are used by MCP servers.
- Langfuse observability was never satisfactory. Strip it entirely and add observability back later using the Phoenix + OTEL stack already deployed in this environment.
- FastMCP 3.x is available; the servers pin `>=2.11.0` with no lock file.

## Migration Order

1. `infra-mcp-server` (pilot -- simplest, no cloud credentials beyond LiteLLM)
2. `mcp-nomad-server` (second priority)
3. `tailscale-mcp-server`
4. `gcp-mcp-server`

## Target Repository Structure

```
terraform/
  mcp-common/                    # pip-installable Python package
    pyproject.toml               # Package metadata + dependencies
    src/mcp_common/
      __init__.py
      server_factory.py          # Simplified: config, FastMCP creation, runner (~100-150 lines)
      llm_factory.py             # LLM client setup (no tracing)
      logging_config.py          # Centralized logging
      http_client/               # Outbound HTTP utilities
      utils/                     # General utilities
    README.md
  infra-mcp-server/
    main.tf                      # 1Password v2 + Nomad + Consul (vm-deployment pattern)
    variables.tf
    infra-mcp-server.nomad.hcl
    Dockerfile
    requirements.txt             # Pinned exact versions, includes mcp-common
    main.py
    config.py
    server_factory.py            # Server-specific factory (uses mcp_common)
    handlers/
    analyzers/
    models/
    utils/
  mcp-nomad-server/              # Same structure
  tailscale-mcp-server/          # Same structure
  gcp-mcp-server/                # Same structure
```

## Key Design Decisions

### mcp-common as a pip-installable package

Standard `pyproject.toml` with `src/` layout. Installed in each server's Dockerfile via `pip install /path/to/mcp-common`. No complex build context sharing -- just a normal Python package install.

### Stripped observability

All Langfuse imports, decorators (`@observe`, `@trace_tool_call`), and tracing modules are removed. No `langfuse` dependency. Handlers use only `@mcp.tool()` decorators. Observability will be added back later using the Arize Phoenix + OpenTelemetry (Tempo + Alloy) stack already deployed in this environment.

### Simplified server factory

The current `server_factory.py` is 682 lines with multiple creation modes, validation modes, and FastAPI integration. Replace with a simplified version (~100-150 lines):

- `MCPServerConfig` dataclass -- server name, host, port, transport, handler modules
- `create_mcp_server()` -- takes config, returns FastMCP instance
- `run_server()` -- takes FastMCP instance, runs with uvicorn
- Auto-discovery of handlers from `handlers/` directory
- No validation modes, no advanced/simple split, no FastAPI integration

### FastMCP 3.x upgrade

- Pin `fastmcp==3.0.2` (or latest 3.x at time of migration)
- Audit for removed constructor kwargs (16 removed in 3.0)
- Handle `ui=` to `app=` rename if applicable
- Fix trailing slash: `redirect_slashes=False`

### Terraform follows vm-deployment patterns

- 1Password provider v2.1.2 (service account token auth via `OP_SERVICE_ACCOUNT_TOKEN`)
- `templatefile()` function for Nomad HCL rendering
- `nomad_variable` resource for secret injection
- Consul service discovery, Traefik routing via Consul tags
- Podman driver, rootless containers
- Secrets evaluated per server during porting, all stored in 1Password

### LLM integration preserved

Servers use LiteLLM (via OpenAI-compatible client) for analysis tools. `llm_factory.py` is kept but stripped of tracing wrappers. LiteLLM URL + API key injected via 1Password to Nomad variables.

## What Gets Removed

- All Langfuse dependencies and integration code
- `agent_mcp/tracing.py`, `llm/workflow_tracing.py`, `llm/mcp_tracing.py`
- A2A protocol code (`a2a_client.py`, `a2a_compat.py`, `a2a_lifecycle.py`)
- Agent workflow code (`agent_langgraph/`, `hybrid_agent.py`, `tool_orchestration.py`)
- FastAPI app scaffolding (`fastapi_app/`)
- MCP client code (`mcp_client.py`, `fastmcp_hub_client.py`)
- Agent config modules (`agent_registry.py`, `vm_config_loader.py`)
- ~70+ files from `common/` that were agent-only

## What Gets Kept (in mcp-common)

- `server_factory.py` -- rewritten/simplified
- `llm_factory.py` -- stripped of tracing
- `logging_config.py` -- centralized logging
- `http_client/` -- outbound HTTP utilities
- Selected `utils/` and `patterns/` modules (determined during port)

## Worktree Strategy

- New worktree created from `feature/app-migration` branch (vm-deployment)
- Branch: `feature/mcp-server-migration`

## Success Criteria

1. All 4 MCP servers deployable from `terraform/<name>/` with no reference to `agent-farm/`
2. `mcp-common` is a proper pip-installable package containing only what servers need
3. All servers on FastMCP 3.x with no deprecated patterns
4. No Langfuse dependency anywhere
5. Terraform follows vm-deployment patterns (1Password v2, templatefile, Nomad variables)
6. Each server builds and runs independently
