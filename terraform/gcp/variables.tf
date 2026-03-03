variable "cloudflare_token" {
  description = "Cloudflare authentication token"
  type        = string
}

provider "cloudflare" {
  api_token = var.cloudflare_token
}

variable "domain_name" {
  description = "Domain managed in Cloudflare"
  default     = "example.com"
}
