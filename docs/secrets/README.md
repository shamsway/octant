# Secret Naming

## General Structure
`{category}_{service}_{type}_{identifier}`

Where:
- `{category}`: The broad category of the secret (e.g., api, host, user, service)
- `{service}`: The specific service or application the secret is for (if applicable)
- `{type}`: The type of secret (e.g., key, password, token, ssh_key)
- `{identifier}`: Additional identifier if needed (e.g., admin, root)

## Categories

1. API Keys and Tokens
   - Description: API keys and tokens for external services
   - Format: `api_{service}_key`
   - Examples:
     - `api_anthropic_key`
     - `api_openai_key`
     - `api_cloudflare_key`
     - `api_github_token`

1. Host Credentials
   - Description: root user credentials
   - Format: `host_{identifier}_creds`
   - Examples:
     - `host_node1_creds`
     - `host_node2_creds`
     - `host_node3_creds`

2. SSH Keys
   - Description: Host or user SSH keys
   - Format: `ssh_{identifier}_key`
   - Examples:
     - `ssh_host_node1_key`
     - `ssh_host_node2_key`
     - `ssh_host_node3_key`
     - `ssh_user_admin_key`
     - `ssh_user_hashi_key`

3. Service Credentials
   - Description: Admin or user credentials for a service
   - Format: `service_{name}`
   - Examples:
     - `service_grafana`
     - `service_influxdb`
     - `service_postgres`
     - `service_homeassistant`

4. Database User Credentials
   - Description: Database user credentials for a service
   - Format: `db_{service}`
   - Examples:
     - `db_langfuse`
     - `db_litellm`
     - `db_n8n`

5. Cloudflare Tunnels
   - Description: API token for Cloudflare Tunnel
   - Format: `tunnel_{service}`
   - Examples:
     - `tunnel_homeassistant`
     - `tunnel_n8n`

6. Miscellaneous
   - `backup_restic_password`
   - `packer_template_root_password`
   - `jupyter_container_token`

## Notes
- For services with multiple types of secrets, use descriptive identifiers:
  - `service_n8n_admin_password`
  - `service_n8n_gcloud_sa_creds`
  - `service_n8n_google_oauth_creds`
- When a service name contains multiple words, use underscores:
  - `api_google_ai_key`

# Secret Names and Descriptions

| New Secret Name                | Old Secret Name                  | Description                                           | Used By                | Required |
|--------------------------------|----------------------------------|-------------------------------------------------------|------------------------|----------|
| `api_1password_connect_token`  | octant connect access token      | export OP_API_TOKEN="<token>"                         | Everything             | Yes      |
| `api_1password_octant_sa_token`| 1password service account token  | export OP_SERVICE_ACCOUNT_TOKEN="<token>"             | testing                | No       |
| `api_anthropic_key`            | Anthropic API Key                | API key for Anthropic                                 | litellm                | Yes      |
| `api_backblaze_creds`          | Backblaze                        | Credentials for Backblaze, used for Restic backups    | .envrc, Restic         | Yes      |
| `api_cloudflare_dns_token`     | Cloudflare DNS Token             | API token for Cloudflare DNS management               | .envrc                 | Yes      |
| `api_cloudflare_key`           | Cloudflare_API_Key               | General API key for Cloudflare services               | n8n                    | Yes      |
| `api_codestral_key`            | Codestral API Key                | API key for Codestral                                 | LiteLLM                | Yes      |
| `api_cohere_key`               | Cohere API Key                   | API key for Cohere AI                                 | LiteLLM                | Yes      |
| `api_github_token`             | Github API Token                 | API token for GitHub operations                       | End user               | No       |
| `api_google_ai_key`            | Googe AI API Key                 | API key for Google AI                                 | End user               | No       |
| `api_groq_key`                 | Groq API Key                     | API key for Groq AI                                   | LiteLLM                | Yes      |
| `api_langfuse_key`             | Langfuse API Key                 | API key for Langfuse                                  | Langfuse Services      | No       |
| `api_mistral_key`              | Mistral API Key                  | API key for Mistral AI                                | LiteLLM                | Yes      |
| `api_nautobot_key`             | Nautobot API Key                 | API key for Natuobot (IPAM)                           | User                   | Yes      |
| `api_openai_key`               | OpenAI API Key                   | API key for OpenAI                                    | LiteLLM                | Yes      |
| `api_openrouter_key`           | Openrouter API Key               | API key for Openrouter                                | LiteLLM                | Yes      |
| `api_promptlayer_key`          | PromptLayer API                  | API key for PromptLayer                               | End user, LiteLLM      | No       |
| `api_replicate_key`            | Replicate API Key                | API key for Replicate AI                              | LiteLLM                | Yes      |
| `api_tailscale_cloud_token`    | Tailscale Cloud Token            | API token for Tailscale Cloud automation              | .envrc                 | Yes      |
| `api_tailscale_key`            | Tailscale-API-Key                | General API key for Tailscale operations              | .envrc                 | Yes      |
| `host_node1_creds`             | billy_creds                      | Root user credentials for node 1, randomly generated  | Node bootstrap         | Yes      |
| `host_node2_creds`             | bobby_creds                      | Root user credentials for node 2, randomly generated  | Node bootstrap         | Yes      |
| `host_node3_creds`             | jerry_creds                      | Root user credentials for node 3, randomly generated  | Node bootstrap         | Yes      |
| `ssh_host_node1_key`           | billy_ssh                        | SSH key for node 1                                    | Node bootstrap         | Yes      |
| `ssh_host_node2_key`           | bobby_ssh                        | SSH key for node 2                                    | Node bootstrap         | Yes      |
| `ssh_host_node3_key`           | jerry_ssh                        | SSH key for node 3                                    | Node bootstrap         | Yes      |
| `ssh_user_root_key`            | root_ssh                         | Root user SSH private key                             | Root User              | Yes      |
| `ssh_user_admin_key`           | matt_ssh                         | Admin user SSH private key                            | Admin User             | Yes      |
| `ssh_user_hashi_key`           | hashi_ssh                        | User SSH private key (automation/lab management)      | Management/automation  | Yes      |
| `service_affine`               |                                  | Credentals for AFFiNE                                 | End user               | No       |
| `service_grafana`              | Grafana                          | Grafana admin password, randomly generated            | End user               | No       |
| `service_homeassistant`        | Home Assistant                   | Home Assistant admin username and password            | End user               | No       |
| `service_influxdb`             | InfluxDB                         | InfluxDB admin password, randomly generated           | End user               | Yes      |
| `service_jupyter`              | jupyter_token                    | Predefined token for Jupyter container                | End user               | No       |
| `service_litellm`              | litellm                          | Litellm admin password, randomly generated            | End user               | Yes      |
| `service_n8n`                  | n8n.shamsway.net                 | n8n admin password, randomly generated                | End user               | Yes      |
| `service_nautobot`             | Nautobot                         | Nautobot (IPAM) admin password, randomly generated    | End user               | Yes      |
| `service_pgadmin`              | pgadmin                          | pgadmin admin credentials, randomly generated         | End user               | Yes      |
| `service_postgres`             | Postgres                         | Postgres admin user credentials, randomly generated   | End user               | Yes      |
| `db_affine`                    |                                  | Postgres credentials for AFFiNE, randomly generated   | AFFiNE                 | No       |
| `db_langfuse`                  | postgres_langfuse                | Postgres credentials for langfuse, randomly generated | Langfuse               | No       |
| `db_litellm`                   | postgres_litellm                 | Postgres credentials for litellm, randomly generated  | Litellm                | No       |
| `db_n8n`                       | postgres_n8n                     | Postgres credentials for n8n, randomly generated      | n8n                    | No       |
| `db_nautobot`                  | nautobot_db                      | Postgres credentials for Nautobot                     | Nautobot               | No       |
| `tunnel_homeassistant`         | homeassistant_cloudflared        | API token for Cloudflare tunnel - Home Assistant      | Home Assistant         | Yes      |
| `tunnel_n8n`                   | n8n_cloudflared                  | API token for Cloudflare tunnel - n8n                 | n8n                    | No       |
| `service_n8n_gcloud_sa_creds`  | n8n_gcloud_sa                    | Google Cloud service account credentials for n8n      | n8n                    | No       |
| `service_n8n_google_oauth_creds` | n8n_google_outh                | Google OAuth credentials for n8n                      | n8n                    | No       |
| `backup_restic_password`        | Restic                         | Restic backup repository password                      | .envrc, Restic         | Yes      |
| `packer_template_root_password` | Debian-Packer-Template          | Root password to embed in Packer builds               | End user               | Yes      |
| `service_dockerhub_creds`      | Docker Hub                       | Credentials for Docker Hub                            | .envrc                 | Yes      |
| `service_1password_connect_creds` | octant connect credentials file | Credentials file for 1password connect              | Everything             | Yes      |
| `api_oracle_cloud_key`         | OCP API keypair                  | API Key for Oracle Cloud                              | Oracle Cloud           | Yes      |
| `api_oracle_cloud_keypair`     | OCP API key                      | Key file contents for Oracle Cloud API                | Oracle Cloud           | Yes      |
| `api_homeassistant_token`      | home assistant token             | Home Assistant API token                              | End user               | No       |

## Conflicting secrets

Some secrets cannot be set at the same time, so those environment variables will need to be unset before running some tasks.

Example with 1password connect:
```
│ Error: Either Connect credentials ("token" and "url") or Service Account ("service_account_token") credentials can be set. Both are set. Please unset one of them.
```

Fix:
```
unset OP_SERVICE_ACCOUNT_TOKEN
```


## Up next
- fix influxdb secret
- fix jupyter secret
- fix homeassistant secret
- document secrets that are not yet ready for use
