## Open WebUI

**Description:** Open WebUI is an open-source UI for interacting with various AI models.

**Use cases:**
- Provide a user-friendly interface for AI model interactions
- Test and compare different AI models
- Integrate AI capabilities into your applications

**Rootless container:** Yes

**Usage:**
- By default, this job assumes Ollama and/or LiteLLM are already deployed.
- Change default variables set in `variables.tf` to match your environment, or set appropriate environment variables.
- Initialize Terraform
```sh
terraform init
```

- Deploy job
```sh
terraform apply -auto-approve
```

**URL:** https://github.com/open-webui/open-webui