## Fusion

**Description:** Lightweight, self-hosted RSS feed reader built with Go and SQLite. Supports RSS/Atom parsing, feed auto-discovery, bookmarks, search, and Fever API for third-party clients.

**Use cases:**
- Monitor RSS feeds for ongoing content tracking
- Complement SearXNG for persistent feed monitoring
- Access feeds from mobile via Fever API-compatible clients (Reeder, Unread, FeedMe)

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

**Login:** Username is always `fusion`. Password is stored in Nomad variable `nomad/jobs/fusion`.

**URL:** `https://fusion.<your-domain>/`
