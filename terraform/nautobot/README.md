## Nautobot

**Description:** Nautobot is a Network Source of Truth and Network Automation Platform.

**Use cases:**
- Manage network inventory
- Generate network documentation
- Automate network configuration tasks

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

**URL:** https://nautobot.com/
