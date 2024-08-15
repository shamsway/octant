# PostgreSQL Backup Job

**Usage:**
- This is a scheduled job that regularly performs a backup of PostgreSQL
- Change default variables set in `variables.tf` or set appropriate environment variables.
- Initialize Terraform
```sh
terraform init
```

- Deploy job
```sh
terraform apply -auto-approve
```