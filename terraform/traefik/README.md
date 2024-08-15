# Traefik

**Note:** Traefik is the rug that ties the room together. Deploy this first!

**Description:** Traefik is a modern HTTP reverse proxy and load balancer.

**Use cases:**
- Automatically configure reverse proxy for Docker containers
- Handle SSL/TLS termination
- Implement service discovery and load balancing

**Rootless container:**
- Traefik: Yes
- Nginx (ingress): No

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

**URL:** https://traefik.io/