Template files to use for Terraform jobs. Nomad job Jinja template is stored in `docs/docker-to-nomad/nomad-job-template.hcl.j2`

## Template

**Description:** Provide a description here

**Use cases:**
- Use case 1
- Use case 2
- Use case 3

**Rootless container:** Yes/No

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

**URL:** https://change.me/