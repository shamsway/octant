# Knowledge Layer Agent Test Prompts

Test prompts for the 4 knowledge team agents via the OpenClaw CLI.

**Recommended order:** 1 (health), 3 (notes, no embedding needed), then 2, 5, 6 once the embedding model is running, and finally 4, 8, 9 for verification.

---

## Archivist (default agent)

### 1. Health check -- verify all backends are reachable

```bash
openclaw agent --message "Check the health of all knowledge backends: Qdrant (http://qdrant.service.consul:6333/healthz), Graphiti (http://graphiti.service.consul:8000/healthcheck), and the Obsidian vault (ls /mnt/services/obsidian/vault/). Report status of each."
```

### 2. Ingestion test -- ingest a small doc to all backends

```bash
openclaw agent --message "Read your SOUL.md and TOOLS.md files. Then ingest the following test content into the 'docs' Qdrant collection and Graphiti (group_id: 'test:knowledge-layer'). Content: 'The Octant homelab runs 3 nodes (octant-01, octant-02, octant-03) on 192.168.122.101-103. It uses Nomad for orchestration, Consul for service discovery, and CephFS for shared storage. Traefik handles ingress with LetsEncrypt certificates via Cloudflare DNS.' Delegate to Vec-Ingest and Graph-Ingest as described in HANDOFFS.md."
```

### 3. Note creation test -- write an Obsidian note

```bash
openclaw agent --message "Create an Obsidian note in the infrastructure folder titled 'Knowledge Layer Test' with content describing the knowledge layer deployment: 4 agents (Archivist, Vec-Ingest, Graph-Ingest, Notes-Ingest), 3 backends (Qdrant, Graphiti, Obsidian). Tag it with 'test' and 'knowledge-layer'. Delegate to Notes-Ingest per HANDOFFS.md."
```

### 4. Retrieval test (after ingestion)

```bash
openclaw agent --message "Search all knowledge backends for information about 'Nomad orchestration'. Query Qdrant docs collection for semantic matches, search Graphiti for related entities, and grep the Obsidian vault. Merge and report results with source attribution."
```

---

## Direct Specialist Tests (via sessions_spawn from Archivist)

### 5. Vec-Ingest direct test

```bash
openclaw agent --message "Spawn a Vec-Ingest session with this task: {\"task\": \"ingest\", \"text\": \"Qdrant is a vector similarity search engine that provides a REST API for nearest-neighbor lookups using high-dimensional vectors.\", \"metadata\": {\"source\": \"test:manual\", \"file_path\": \"test/vec-ingest-test.md\", \"section_heading\": \"Overview\", \"timestamp\": \"2026-03-05T22:00:00Z\", \"content_type\": \"markdown\"}, \"collection\": \"docs\"}. Report the result."
```

### 6. Graph-Ingest direct test

```bash
openclaw agent --message "Spawn a Graph-Ingest session with this task: {\"task\": \"ingest\", \"text\": \"LiteLLM is a proxy that routes API calls to multiple LLM providers. In the Octant lab, it proxies to a local vLLM instance running on AMD MI300X GPUs. It also provides an embedding endpoint using bge-large-en-v1.5.\", \"metadata\": {\"source\": \"test:manual\", \"file_path\": \"test/graph-ingest-test.md\", \"timestamp\": \"2026-03-05T22:00:00Z\"}, \"group_id\": \"test:knowledge-layer\"}. Report the result including any entities and relationships extracted."
```

### 7. Notes-Ingest direct test

```bash
openclaw agent --message "Spawn a Notes-Ingest session with this task: {\"task\": \"create\", \"title\": \"Vec-Ingest Test Results\", \"content\": \"## Test Run\\n\\nVec-Ingest successfully embedded test content into the docs collection.\\n\\n- Collection: docs\\n- Points upserted: 1\\n- Embedding model: bge-large-en-v1.5 (1024 dims)\", \"folder\": \"agents\", \"tags\": [\"test\", \"vec-ingest\"], \"frontmatter\": {\"source\": \"test:manual\", \"created\": \"2026-03-05T22:00:00Z\"}}. Report the file path and action."
```

---

## Verification Prompts (run after the above)

### 8. Verify Qdrant has data

```bash
openclaw agent --message "Check how many points are in each Qdrant collection (docs, notes, configs) by querying GET http://qdrant.service.consul:6333/collections/{collection} for each. Report the point counts."
```

### 9. Verify Obsidian note was written

```bash
openclaw agent --message "List all files in the Obsidian vault at /mnt/services/obsidian/vault/ recursively, and show the content of any .md files you find."
```
