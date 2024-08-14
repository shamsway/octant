## pgAdmin

**Description:** pgAdmin is a management tool for PostgreSQL and derivative relational databases.

**Use cases:**
- Manage PostgreSQL databases through a web interface
- Execute SQL queries and scripts
- Monitor database performance

**Rootless container:** Yes

**Note:** This job was initially bundled with Postgres, so this job needs to be tested to ensure it's working as intended.

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

**URL:** https://www.pgadmin.org/
