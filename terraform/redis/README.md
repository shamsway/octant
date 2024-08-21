# Redis

**Description:** Redis is an open-source, in-memory data structure store, used as a database, cache, and message broker.

**Use cases:**
- Cache frequently accessed data
- Implement pub/sub messaging systems
- Store session data for web applications

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

**URL:** https://redis.io/
