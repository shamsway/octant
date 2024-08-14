## PostgreSQL

**Description:** PostgreSQL is a powerful, open-source object-relational database system.

**Use cases:**
- Store and manage relational data for applications
- Perform complex queries and data analysis
- Serve as a backend for web applications

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

**URL:** https://www.postgresql.org/
