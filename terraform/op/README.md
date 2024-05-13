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

## Test

```bash
curl \
-H "Accept: application/json" \
https://opapi.shamsway.net/health
```

```bash
curl \
-H "Accept: application/json" \
https://opsync.shamsway.net/health
```

```bash
curl \
-H "Accept: application/json" \
-H "Authorization: Bearer $OP_API_TOKEN" \
https://opapi.shamsway.net/v1/vaults
```
# Finding UUIDs

- In 1password GUI, right click -> copy link/copy private link
- Result `https://start.1password.com/open/i?a=[ACCOUNT]&v=[VAULT]&i=[ITEM]&h=my.1password.com`

Import an password into Terraform:
`terraform import onepassword_item.postgres_pass vaults/[VAULT]/items/[ITEM]`

## Scratch pad

`terraform import onepassword_item.postgres_pass vaults/naswcsgqw4zzkluj6zbd3r2qfq/items/2hgfrtvnyev6q7fojuj5gwiwx4`

      template {
        destination = "$${NOMAD_SECRETS_DIR}/env.txt"
        env         = true
        data        = <<EOT
{{ with nomadVar "nomad/jobs/postgres" }}PGWEB_DATABASE_URL=postgres://postgres:{{ .postgres_password }}@postgres.sevice.consul:5432/pgweb?sslmode=disable{{ end }}
EOT
      }    

```hcl
resource "onepassword_item" "postgres_pass" {
  vault = data.onepassword_vault.dev.uuid

  title    = "Postgres"
  category = "password"
  password_recipe {
    length  = 12
    symbols = true
  }  
}
```

OP_BUS_PEERS="{{ range nomadService "opsyncbus" }}{{ .Address }}:{{ .Port }}{{ end }}"

# Kubernetes/Helm

This is not relevant to Octant, but worth properly documenting. When using Helm/Kubernetes, it appears the variable should be double encoded. Here are the key points that support this conclusion:

1. Multiple users have reported encountering the same error message when setting `OP_SESSION` to the file path:
   ```
   "Server: (unable to get credentials and initialize API, retrying in 30s), Wrapped: (failed to FindCredentialsUniqueKey), failed to loadCredentialsFile: Server: (LoadLocalAuthV2 failed to credentialsDataFromBase64), illegal base64 data at input byte 7"
   ```
   This error suggests that the container is expecting the value of `OP_SESSION` to be base64-encoded data, not a file path.

2. Users have found success by double-encoding the contents of the `1password-credentials.json` file in base64 format and setting `OP_SESSION` to that value. This workaround indicates that the container is expecting the credentials to be provided as base64-encoded data.

3. One user mentioned that when they set `OP_SESSION` to the file path, the container received the plain JSON contents of the file instead of the base64-encoded data. This suggests that the container is not correctly handling the file path and is expecting the base64-encoded data directly.

4. The documentation for the `OP_SESSION` variable states:
   ```
   You can also set the value to the Base64-encoded content of the `1password-credentials.json` file.
   ```
   This implies that providing the base64-encoded content of the file is a valid option.

Based on these observations, it appears that the intended behavior of the `OP_SESSION` variable is to accept the base64-encoded content of the `1password-credentials.json` file, rather than the file path. The fact that users have to double-encode the contents suggests that there might be a bug or an undocumented requirement in the container implementation.

To ensure compatibility and avoid the encountered errors, it is recommended to set `OP_SESSION` to the double-encoded base64 contents of the `1password-credentials.json` file, as described in the previous response.

However, it is important to note that this behavior deviates from the documented acceptable values for `OP_SESSION`, which state that it should be a full file path to the `1password-credentials.json` file.

- https://1password.community/discussion/131378/loadlocalauthv2-failed-to-credentialsdatafrombase64
- https://github.com/1Password/connect/issues/62
- https://1password.community/discussion/124432/unable-to-get-credentials-and-initialize-api-read-home-opuser-op-1password-credentials-json
- https://1password.community/discussion/142716/connect-server-failed-to-retrieve-credentials


## Podman Commands

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