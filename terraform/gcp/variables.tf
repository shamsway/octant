variable "cloudflare_token" {
  description = "Cloudflare authentication token"
  type        = string
}

provider "cloudflare" {
  api_token = "${var.cloudflare_token}"
}

variable "domain_name" {
  default = "shamsway.net"
}

# variable "TAILSCALE_KEY" {
#   description = "Tailscale authentication key"
#   type        = string
# }