## PlantUML

**Description:** PlantUML is an open-source tool that allows you to create UML diagrams from a plain text language.

**Use cases:**
- Generate UML diagrams for software documentation
- Create sequence diagrams, use case diagrams, and more
- Integrate diagram generation into documentation workflows

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

**URL:** https://plantuml.com/