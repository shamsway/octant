**Description:** LiteLLM is a library that provides a uniform interface to different LLM providers.

**Use cases:**
- Simplify integration with multiple LLM providers in your applications
- Standardize LLM API calls across different services

**URL:** https://github.com/BerriAI/litellm

**Rootless container:** Yes

**Prerequisites:**

The LiteLLM database and role must exist in PostgreSQL before deploying.
Connect as the `postgres` superuser and run:

```sql
CREATE ROLE litellm WITH LOGIN PASSWORD '<password from db_litellm in 1Password>';
CREATE DATABASE litellm OWNER litellm;
GRANT ALL PRIVILEGES ON DATABASE litellm TO litellm;
```

Example using `psql`:
```sh
psql -h postgres.service.consul -U postgres -W
```

**Observability:**

Traces are sent to Arize Phoenix via the `arize_phoenix` callback. The
`PHOENIX_COLLECTOR_HTTP_ENDPOINT` env var is set automatically by the Nomad
job template using Consul service discovery — no manual endpoint config needed.
See `config.phoenix.yaml.example` for details.

**Usage:**
- Copy `config.yaml.example` to `config.yaml` and adjust as needed.
  - See `config.local-models.yaml.example` for adding local OpenAI-compatible endpoints.
  - See `config.phoenix.yaml.example` for Phoenix observability setup.
- Review `main.tf` and ensure all secrets are configured.
- Initialize Terraform
```sh
terraform init
```
- Deploy job
```sh
terraform apply -auto-approve
```
- To pick up config changes, destroy and re-apply:
```sh
terraform destroy -auto-approve && terraform apply -auto-approve
```
