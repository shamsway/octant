Template files to use for Terraform jobs. Nomad job Jinja template is stored in `docs/docker-to-nomad/nomad-job-template.hcl.j2`

## Linkding

**Description:** Self-hosted bookmark manager with tagging, full-text search, auto-fetch of titles/descriptions, browser extensions, and REST API. Uses SQLite for storage.

**Use cases:**
- Save and organize bookmarks with tags
- Auto-fetch page titles and descriptions
- Full-text search across all bookmarks
- REST API for integrations (e.g., browser extensions, n8n)

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

**URL:** https://linkding.lab.shamsway.net/
