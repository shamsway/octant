## Graphiti

**Description:** Temporal knowledge graph framework for AI agents. Ingests unstructured text, extracts entities and relationships via LLM, and builds a queryable knowledge graph with temporal awareness. Exposes REST API and MCP server.

**Use cases:**
- Persistent knowledge graph from conversations, documents, and events
- AI agent memory via MCP — "what do I know about X?" with temporal awareness
- GraphRAG patterns for context-aware retrieval

**Rootless container:** Yes (requires `user = "root"` override — image installs uv in `/root/.local/bin/` but sets `USER app`)

**Dependencies:**
- **Neo4j** — graph storage backend (must be running, registered as `neo4j-bolt` in Consul)
- **LiteLLM** — LLM proxy for entity/relationship extraction (OpenAI API key = LiteLLM master key)

**Prerequisites:**
1. Deploy Neo4j and create its Nomad variable:
```sh
nomad var put nomad/jobs/neo4j NEO4J_PASSWORD="your-secure-password"
```
2. Ensure LiteLLM is running (`nomad job status litellm`)

**Usage:**
- Initialize Terraform
```sh
terraform init
```

- Deploy job
```sh
terraform apply -auto-approve
```

**Ports:**
- 8000 — REST API (Traefik-routed)

**Volumes:** None (stateless — all state lives in Neo4j)

**Health check:** `/healthcheck`

**Note:** The official `zepai/graphiti:latest` Docker image only supports Neo4j, not FalkorDB. FalkorDB support exists in the Python library but not the server image ([tracking issue](https://github.com/getzep/graphiti/issues/749)).

**URL:** https://graphiti.lab.shamsway.net/

**Project:** https://github.com/getzep/graphiti
