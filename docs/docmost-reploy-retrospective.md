---
Docmost Deployment Retrospective
Date: 2026-03-03
Service: Docmost (collaborative wiki/documentation platform)
Tier: Medium (M1) — PostgreSQL + Redis dependencies
Outcome: Successful first-attempt deployment, zero rollbacks
Time: ~5 minutes from first prompt to verified HTTPS 200

---
The Prompt

A single sentence: deploy Docmost using the octant-autodeploy plugin, referencing the candidate design doc. No hand-holding, no step-by-step instructions from the user. The expectation was that the skill system would provide the structure, the reference doc would provide the context, and the agent would do the rest.

Phase 0: Orientation (What Do I Know?)

The first thing I did was read two documents in parallel:

1. The autodeploy skill (octant-autodeploy/SKILL.md) — This is the orchestration skill. It doesn't do the work itself; it's a routing table. It told me the deployment has phases (0 through 5), and for each phase, which specialized skill to consult. It also gave me the Nomad job template, Terraform template, variable escaping rules, and the validation checklist.
2. The candidate design doc (2026-02-27-autodeploy-candidates-design.md) — This told me everything about Docmost specifically: image name, port 3000, dependencies (Postgres + Redis), volume mount path (/app/data/storage), env vars (APP_URL, APP_SECRET, DATABASE_URL, REDIS_URL), and even a pre-adapted compose reference already pointing at postgres.service.consul and redis.service.consul.

The design doc was doing a lot of heavy lifting here. It had already translated the upstream Docker Compose into lab-specific terms. That's a pattern worth noting — the design doc wasn't just "here's what Docmost is," it was "here's how Docmost maps to this specific lab." That pre-analysis is what made the actual deployment mechanical rather than investigative.

Phase 0: Service Discovery

Before touching anything, the autodeploy skill says: check what already exists. I read the octant-consul-discovery skill, then ran three commands
in parallel:

- consul catalog services — to see all registered services
- nomad job status -short — to see all running jobs
- Redis DB size scan — to find available database numbers

Discovery: Consul DNS didn't resolve from the worktree. This is a recurring theme in this lab — when you're working from a git worktree or a dev machine, *.service.consul DNS doesn't resolve because you're not on a cluster node. I adapted on the fly, using 192.168.122.101 (node IP) for psql commands later. This is exactly the kind of tip I flagged in the skill feedback.

Redis allocation: The scan for used Redis DBs was inconclusive via the recommended nomad job inspect | jq approach, because most services put their Redis URL in Nomad template blocks (sourced from Nomad variables), not in the Env block that jq was searching. I fell back to grepping the actual .nomad.hcl files across terraform/*/, which revealed nautobot using DB 0/1. I allocated DB 2 for Docmost.

Phase 1: Prerequisites — The Four-Skill Orchestration

This is where the skill system really showed its value. The autodeploy skill told me I needed four things, and pointed me to four specialized
skills:

1. PostgreSQL (octant-postgres skill)

The skill gave me the exact commands:
- Get admin password from 1Password via op read
- CREATE DATABASE docmost
- CREATE USER docmost WITH PASSWORD '...'
- GRANT ALL PRIVILEGES, ALTER DATABASE ... OWNER TO, GRANT ALL ON SCHEMA public
- Store credentials in 1Password as db_docmost

The Postgres 15+ schema grant (GRANT ALL ON SCHEMA public) is the kind of thing you'd forget without the skill documenting it. Pre-15, the public schema was world-writable. Post-15, you have to explicitly grant it. A subtle gotcha that the skill handles by including it in every setup.

2. Redis (octant-redis skill)

Straightforward — allocate DB 2, no authentication needed (internal network). The skill confirmed the convention: DB 0 = default (avoid), 1-9 = production apps.

3. Secrets (octant-secrets-management skill)

Generated APP_SECRET (64-char hex via openssl rand -hex 32) and created the Nomad variable at nomad/jobs/docmost with all connection details:
- db_host, db_port, db_name, db_user, db_password
- app_secret
- redis_url

The Nomad variable is the secret distribution mechanism — the Nomad job template reads from it at runtime using {{ with nomadVar "nomad/jobs/docmost" }}. No secrets in HCL files, no secrets in Terraform state (they're referenced, not stored).

4. Volumes (octant-volumes skill)

Added one volume entry to inventory/groups.yml:
- name: docmost-storage
  path: /mnt/services/docmost/storage
  backup: true

Then ran the Ansible playbook: ansible-playbook playbooks/05-deploy-volumes.yml -i inventory/provisioned_vms.yml -i inventory/groups.yml

The skill's warning — "Do NOT use make deploy-role ROLE=volumes" — saved me from a common mistake. The volumes role isn't in the main playbook, so the make target silently does nothing.

CephFS created the directory on octant-01 (changed=1) and it propagated automatically to octant-02 and octant-03 (changed=0, already visible via CephFS).

Phase 2: Configuration Generation — Pattern Matching

This is where I wrote the three files. But I didn't write them from scratch — I used two sources:

1. The autodeploy skill's templates — for the structural skeleton
2. An existing similar deployment — I read terraform/linkwarden/ (all three files) because Linkwarden is the closest analog: same port (3000), same tier (medium), PostgreSQL dependency, Next.js/Node.js runtime, Nomad variables for secrets

From linkwarden I picked up patterns the template didn't include:
- image_pull_timeout = "15m" — essential for first pulls of large images
- traefik.consulcatalog.connect=false — the Traefik tag the template was missing
- attr.kernel.name constraint — belt-and-suspenders with meta.rootless
- The exact locals/templatefile structure in main.tf

The three files:

docmost.nomad.hcl — The Nomad job spec. Key decisions:
- Port 3000 (from Docmost docs)
- Health check on / (Node.js app, no dedicated /health endpoint — verified via web search)
- 1024MB memory (Node.js/NestJS sizing guide)
- 500 CPU MHz
- Volume mount: /mnt/services/docmost/storage:/app/data/storage
- Template block for secrets from Nomad variables
- APP_URL in env block (not secrets — it's the public URL)

main.tf — Terraform config. Exactly matches the lab pattern: nomad provider, templatefile() with locals, no consul backend (local state for now).

variables.tf — Variable definitions with lab defaults: octant datacenter, home region, DNS servers, octant.local domain (overridden by .envrc to
lab.shamsway.net).

Phase 3: Validation — The Safety Net

Three commands:
1. terraform init — downloaded the nomad provider
2. terraform validate — syntax check passed
3. terraform plan — this is where the real validation happened

The plan output was the moment of truth. I could see the fully-rendered jobspec with:
- All ${var} tokens resolved to actual values (docmost, home, octant)
- All $${} tokens correctly preserved as ${} for Nomad runtime (${attr.kernel.name}, ${meta.rootless}, ${NOMAD_SECRETS_DIR})
- Traefik router rule pointing to docmost.lab.shamsway.net
- DNS servers correctly JSON-encoded as an array
- Template block with {{ with nomadVar ... }} Go template syntax intact

No errors. One resource to create.

Phase 4: Deploy — The Moment

terraform apply -auto-approve

One resource created in under a second. Nomad accepted the job and started scheduling.

Phase 5: Verification — Trust But Verify

First check (9 seconds after submit): Status pending — still pulling the image.

Second check (43 seconds): Status running — container started.

Logs: 28 database migrations executed successfully, then: "Listening on http://127.0.0.1:3000 / https://docmost.lab.shamsway.net"

Third check (1 minute 10 seconds): Deployment status successful, health check healthy.

HTTPS verification: curl -skI https://docmost.lab.shamsway.net/ returned HTTP 200 with text/html content type.

From terraform apply to verified HTTPS 200: approximately 75 seconds.

What Made This Work

The skill system as institutional memory. Each skill encodes lessons learned from previous deployments. The Postgres 15 schema grant. The traefik.consulcatalog.connect=false tag. The volumes playbook path. The image_pull_timeout. These aren't things you'd know from reading upstream documentation — they're specific to this lab, learned through failure, and preserved in the skills so they don't have to be re-learned.

The design doc as pre-analysis. The candidate design doc had already done the hardest cognitive work: mapping Docmost's upstream requirements to this lab's specific infrastructure. Database at postgres.service.consul:5432, Redis at redis.service.consul:6379, volume at /app/data/storage, env vars. By the time I started the deployment, the "what do I need to figure out" phase was already done.

Existing deployments as reference implementations. Reading linkwarden's actual deployed config was more useful than the skill's template alone. Real deployments accumulate practical details (pull timeouts, tag orderings, constraint patterns) that templates idealize away.

The phased workflow as guard rails. Phase 0 (discovery) before Phase 1 (prerequisites) before Phase 2 (config) before Phase 3 (validation) before Phase 4 (deploy). Each phase has a clear exit condition. You can't accidentally skip creating the database or forget to create volumes because the workflow makes each prerequsite explicit.

The Broader Arc

This deployment was the M1 (Medium Tier, Top Pick) candidate from a design doc written on 2026-02-27. The skills it exercised — octant-autodeploy, octant-postgres, octant-redis, octant-volumes, octant-secrets-management, octant-validation, octant-consul-discovery — represent a suite of specialized knowledge that has been iteratively refined across deployments of IT-Tools, Linkding, Fusion, Linkwarden, Gitea, NATS, FalkorDB, Neo4j, Graphiti, MongoDB, Rocket.Chat, and now Docmost.

Each of those deployments encountered problems. Template newline gotchas. Consul service name mismatches. Image USER/entrypoint conflicts. Rootless permission failures. Volume propagation races. Each problem became a lesson, each lesson became a skill update, and each skill update made the next deployment smoother.

Docmost was the deployment where it all came together. Not because it was trivial — it has real dependencies (Postgres, Redis), real secrets management (1Password, Nomad variables), real infrastructure (CephFS volumes, Traefik routing, Consul discovery) — but because the accumulated knowledge in the skill system made each step predictable. No surprises, no rollbacks, no "let me check the logs to figure out what went wrong."

The Shadout Mapes quote is apt. The vision — "I should be able to say 'deploy this service' and have an agent walk through a structured workflow, consulting specialized knowledge at each step, and produce a running service" — was the prophecy. Two years of model iterations, skill refinements, plugin architecture changes, and deployment failures were the long wait. This deployment was the revelation.

And like all good revelations, it felt almost anticlimactic in the moment. It just... worked. Which is exactly the point.
