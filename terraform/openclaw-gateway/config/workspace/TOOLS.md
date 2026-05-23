# TOOLS.md — Engineering Equipment

## Operating Pattern

- **Captain:** Matt (the user)
- **Primary tools:** LiteLLM model routing, Consul service discovery, Nomad job status
- **Before any status report:** Actually check the system — never report from memory alone

## LLM Models

Access via LiteLLM proxy at `http://litellm.service.consul:4000`.

| Model | Strengths | Notes |
|-------|-----------|-------|
| `local/deepseek-v3.2` | Reasoning, code, SWE-Bench leader | The big brain — send her the hard problems |
| `local/glm-5-fp8` | General purpose, fast, coding | Battle-tested, reliable workhorse |
| `local/qwen-3.5` | Agentic tasks, 262K context | Long documents, extended conversations |
| `local/mimo-v2-flash` | Fast lightweight tasks | Quick turnaround, simple queries |

Model availability depends on what's loaded in vLLM on the hypervisor. Check before promising a specific model.

## Infrastructure Services

| Service | Endpoint | Purpose |
|---------|----------|---------|
| LiteLLM | `litellm.service.consul:4000` | Model routing proxy |
| Consul | `consul.service.consul:8500` | Service discovery, health checks |
| Nomad | `nomad.service.consul:4646` | Job orchestration |
| Phoenix | `phoenix.service.consul` | LLM observability |
| Qdrant | `qdrant.service.consul` | Vector search |

## MCP Servers

If MCP servers are available in this cluster, register them in `mcporter.json`:

- **nomad-mcp:** `http://mcp-nomad-server.service.consul:30859/mcp` — Nomad job management
- **infra-mcp:** `http://infra-mcp-server.service.consul:26378/mcp` — System health, disk, memory

## Lessons Learned

- LiteLLM model names must match exactly what vLLM serves — check `/v1/models` endpoint
- Consul DNS works from inside the container (aardvark-dns in Podman 4.x)
- Model hot-reload in LiteLLM doesn't require gateway restart
- Tool policy changes in openclaw.json DO require gateway restart
