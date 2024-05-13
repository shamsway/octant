To run the n8n container using Podman from the command line in rootless mode, you can use the following command:

```bash
podman run -d --name n8n \
  -p 5678:5678 \
  -e N8N_BASIC_AUTH_ACTIVE=false \
  -e N8N_PORT=5678 \
  -e DB_TYPE=postgresdb \
  -e DB_POSTGRESDB_HOST=postgres \
  -e DB_POSTGRESDB_PORT=5432 \
  -e DB_POSTGRESDB_DATABASE=${POSTGRES_DB} \
  -e DB_POSTGRESDB_USER=${POSTGRES_NON_ROOT_USER} \
  -e DB_POSTGRESDB_PASSWORD=${POSTGRES_NON_ROOT_PASSWORD} \
  -v n8n:/home/node/.n8n \
  docker.n8n.io/n8nio/n8n:${N8N_VERSION}
```

Make sure to replace the environment variables (`${POSTGRES_DB}`, `${POSTGRES_NON_ROOT_USER}`, `${POSTGRES_NON_ROOT_PASSWORD}`, `${N8N_VERSION}`) with their actual values.

This command will start the n8n container in detached mode (-d), map the container's port 5678 to the host's port 5678 (-p 5678:5678), set the necessary environment variables (-e), and mount the n8n volume to /home/node/.n8n inside the container (-v n8n:/home/node/.n8n).

Note that the Podman command assumes that the `n8n` volume is already created. If the volume doesn't exist, you can create it using the following command:

```bash
podman volume create n8n
```

After running the container, you should be able to access n8n at `http://localhost:5678`.

## Scratch

podman run --rm --name n8n \
  -p 5678:5678 \
  -e N8N_BASIC_AUTH_ACTIVE=false \
  -e N8N_PORT=5678 \
  -e DB_TYPE=postgresdb \
  -e DB_POSTGRESDB_HOST=192.168.252.6 \
  -e DB_POSTGRESDB_PORT=5432 \
  -e DB_POSTGRESDB_DATABASE=n8n \
  -e DB_POSTGRESDB_USER=postgres_n8n \
  -e DB_POSTGRESDB_PASSWORD='' \
  -v n8n:/home/node/.n8n \
  docker.n8n.io/n8nio/n8n:1.40.0