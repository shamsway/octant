# DNS Setup

Octant supports two DNS tiers for service routing through Traefik.

## Tier 1: sslip.io (Default, Zero Config)

By default, services are accessible via sslip.io-based hostnames that encode the Traefik node's IP address. No DNS configuration required.

**How it works:**
- `service_domain` defaults to `192-168-122-101.sslip.io`
- Services are accessible at `grafana.192-168-122-101.sslip.io`, etc.
- sslip.io is a public DNS service that resolves these hostnames to `192.168.122.101`
- Works on locked-down clients without changing DNS resolvers
- HTTP only (no TLS certificates)

**Limitations:**
- No HTTPS (cannot obtain Let's Encrypt certs for sslip.io subdomains)
- Some corporate DNS resolvers may block sslip.io (DNS rebinding protection)
- Long, ugly hostnames

## Tier 2: Cloudflare + Real Domain (Opt-In)

For production-grade HTTPS with valid certificates, use a real domain with Cloudflare.

**Setup steps:**

1. **Register or use an existing domain** on Cloudflare (free tier works)

2. **Create a Cloudflare API token** with Zone:DNS:Edit permissions

3. **Store the API token in 1Password** vault "Octant":
   - Create an item titled "Cloudflare API Token" with the token as the password
   - Note the email associated with your Cloudflare account

4. **Create a wildcard DNS record** in Cloudflare:
   - Type: A
   - Name: `*.lab` (or your chosen subdomain)
   - Content: `192.168.122.101` (your Traefik node IP)
   - Proxy status: **DNS only** (grey cloud) - required for private IPs
   - This enables `grafana.lab.yourdomain.com`, `prometheus.lab.yourdomain.com`, etc.

5. **Update `inventory/group_vars/all.yml`:**
   ```yaml
   service_domain: "lab.yourdomain.com"
   service_certresolver: "cloudflare"
   ```

6. **Update `.env` with Cloudflare credentials** (used by Traefik module):
   ```
   cloudflare_username=your-email@example.com
   cloudflare_api_key=your-api-key
   ```

7. **Redeploy services:**
   ```bash
   make deploy-services
   ```

Traefik will automatically obtain a wildcard Let's Encrypt certificate via DNS-01 challenge.

**Subdomain support:**
- Using `lab.octant.net` as the domain creates services at `grafana.lab.octant.net`
- Cloudflare free tier supports DNS-only wildcards at any depth
- Let's Encrypt DNS-01 works with subdomains (TXT record at `_acme-challenge.lab.octant.net`)

## Switching Tiers

To switch from Tier 1 to Tier 2:
1. Follow the Tier 2 setup steps above
2. Run `make deploy-services` to update all Traefik routes

To switch back to Tier 1:
1. Set `service_domain` back to sslip.io value
2. Set `service_certresolver` to empty string
3. Run `make deploy-services`
