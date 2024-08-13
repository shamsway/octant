# 1Password Connect

## Docs

- https://developer.1password.com/docs/connect/get-started/
- https://developer.1password.com/docs/connect/connect-server-configuration

## Credentials File

Per `https://developer.1password.com/docs/connect/connect-server-configuration`: 

```
Environment variable	  Description

OP_SESSION	            The path to the 1password-credentials.json file. You can also set the value to the Base64-encoded content of the 1password-credentials.json file. Acceptable values: A full file path to the 1password-credentials.json file. Default value: ~/.op/1password-credentials.json
```

Unfortunately this doesn't seem to work. It appears that the `OP_SESSION` environment variable should be set to the encoded base64 contents of the `1password-credentials.json` file, rather than the file path. 

## Testing

Replace `octant.net` with your domain name

```bash
curl \
-H "Accept: application/json" \
https://opapi.octant.net/health
```

```bash
curl \
-H "Accept: application/json" \
https://opsync.octant.net/health
```

```bash
curl \
-H "Accept: application/json" \
-H "Authorization: Bearer $OP_API_TOKEN" \
https://opapi.octant.net/v1/vaults
```

```bash
curl \
-H "Accept: application/json" \
-H "Authorization: Bearer $OP_API_TOKEN" \
https://opapi.octant.net/v1/vaults/[vaultid]/items
```

## Finding UUIDs

- In 1password GUI, right click -> copy link/copy private link
- Result `https://start.1password.com/open/i?a=[ACCOUNT]&v=[VAULT]&i=[ITEM]&h=my.1password.com`

Import an password into Terraform:
`terraform import onepassword_item.postgres_pass vaults/[VAULT]/items/[ITEM]`

## Terraform Integration

Links:
- https://developer.1password.com/docs/terraform/
- https://github.com/1Password/terraform-provider-onepassword
- https://registry.terraform.io/providers/1Password/onepassword/latest

## Ansible Integration

Link: https://developer.1password.com/docs/connect/ansible-collection/

### Steps

Install the onepassword.connect collection from Ansible Galaxy. 

`ansible-galaxy collection install onepassword.connect`

Add onepassword.connect to the task collections.

```yaml
collections:
    - onepassword.connect  # Specify the 1Password collection
```
Provide the Connect server token through the `token` variable in the Ansible task or the `OP_CONNECT_TOKEN` environment variable. You must set this value in each Ansible task.

It's best practice to use a local variable to set the Connect server token because it's more secure.  The following example sets the `connect_token` variable to the Connect server token value, then references it for the `token` field.

```yaml
vars:
    connect_token: "<connect-server-token>"  # Set the Connect server token
collections:
    - onepassword.connect  # Specify the 1Password collection
tasks:
    - onepassword.connect.generic_item:
        token: "{{ connect_token }}"
```

Provide the Connect server hostname, IP address, or URL through the `hostname` variable in the Ansible task or the `OP_CONNECT_HOST` environment variable. You must set this value in each Ansible task.

```yaml
environment:
    OP_CONNECT_HOST: <connect-host>  # Set the Connect server hostname
collections:
    - onepassword.connect  # Specify the 1Password collection
```

The following example uses the `item_info` module to find a 1Password item by name.

```yaml
  hosts: localhost
  vars:
    connect_token: "<connect-server-token>"  # Set the Connect server token
  environment:
    OP_CONNECT_HOST: <connect-host>  # Set the Connect server hostname
  collections:
    - onepassword.connect  # Specify the 1Password collection
  tasks:
    - name: Find the item with the label "Staging Database" in the vault "Staging Env"
      item_info:
        token: "{{ connect_token }}"
        item: Staging Database
        vault: Staging Env
      no_log: true  # Turn off logs to avoid logging sensitive data
      register: op_item
```

More examples at: https://developer.1password.com/docs/connect/ansible-collection/

## Running under Podman

Use these commands to run the containers under Podman for testing/troubleshooting.

### API

podman run -d --name op-connect-api \
  -p 8080:8080 \
  -v ./1password-credentials.json:/home/opuser/.op/1password-credentials.json:ro \
  -v op-connect-data:/home/opuser/.op/data \
  1password/connect-api:latest

### Sync

  podman run -d --name op-connect-sync \
  -p 8081:8080 \
  -v ./1password-credentials.json:/home/opuser/.op/1password-credentials.json:ro \
  -v op-connect-data:/home/opuser/.op/data \
  1password/connect-sync:latest