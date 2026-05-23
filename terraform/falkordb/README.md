## FalkorDB

**Description:** High-performance graph database optimized for GraphRAG and AI/ML workloads. Redis-protocol-compatible with Cypher query support via `GRAPH.QUERY`. Includes a web browser UI.

**Use cases:**
- Knowledge graphs for GraphRAG patterns
- Relationship queries for AI agent memory (Graphiti backend)
- Lightweight Neo4j alternative using familiar Redis protocol

**Rootless container:** Yes

**Usage:**
- Create a Nomad variable with the FalkorDB password before deploying:
```sh
nomad var put nomad/jobs/falkordb FALKORDB_PASSWORD="your-secure-password"
```
- Change default variables set in `variables.tf` or set appropriate environment variables.
- Initialize Terraform
```sh
terraform init
```

- Deploy job
```sh
terraform apply -auto-approve
```

**Ports:**
- 6379 — Redis protocol for graph queries (internal, no Traefik)
- 3000 — Web browser UI (Traefik-routed)

**Volumes:**
- `/mnt/services/falkordb/data` → `/data` (graph persistence)

**Port conflict note:** FalkorDB uses Redis protocol on port 6379 but is NOT the existing Redis instance. Nomad network namespace isolation prevents conflicts — each service gets its own dynamic host port mapped to the container port. Access via Consul service discovery at `falkordb.service.consul`.

**URL:** https://falkordb.lab.shamsway.net/

**Project:** https://github.com/FalkorDB/FalkorDB
