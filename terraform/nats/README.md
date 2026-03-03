## NATS (with JetStream)

**Description:** High-performance messaging system with JetStream persistence for pub/sub, request/reply, key-value store, and object store. Lightweight alternative to Kafka/RabbitMQ — single binary, ~20MB.

**Use cases:**
- Event bus for decoupled communication between lab services (n8n, Windmill, Graphiti)
- JetStream key-value store for lightweight configuration sharing
- Persistent at-least-once message delivery between producers and consumers

**Rootless container:** Yes

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

**Ports:**
- 4222 — Client connections (internal, no Traefik)
- 8222 — HTTP monitoring API (Traefik-routed)

**Volumes:**
- `/mnt/services/nats/data` → `/data/jetstream` (JetStream persistence)

**Monitoring endpoints:**
- `/healthz` — Health check
- `/varz` — Server stats
- `/connz` — Connection info
- `/routez` — Route info
- `/subsz` — Subscription info

**Project:** https://github.com/nats-io/nats-server
