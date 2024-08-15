**Description:** LiteLLM is a library that provides a uniform interface to different LLM providers.

**Use cases:**
- Simplify integration with multiple LLM providers in your applications
- Standardize LLM API calls across different services

**URL:** https://github.com/BerriAI/litellm

**Rootless container:** Yes

**Usage:**
- Copy `config.yaml.example` to `config.yaml` and adjust as needed.
- Review `main.tf` and ensure all secrets are configured.
- Initialize Terraform
```sh
terraform init
```
- Deploy job
```sh
terraform apply -auto-approve
```