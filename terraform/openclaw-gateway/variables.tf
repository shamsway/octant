variable "op_vault_name" {
  description = "1Password vault name"
  type        = string
  default     = "Octant"
}

variable "nomad" {
  description = "Nomad server address"
  type        = string
  default     = "localhost"
}

variable "consul" {
  description = "Consul server address"
  type        = string
  default     = "localhost"
}

variable "region" {
  type    = string
  default = "home"
}

variable "datacenter" {
  type    = string
  default = "octant"
}

variable "image" {
  description = "OpenClaw gateway container image"
  type        = string
  default     = "192.168.122.1:5000/openclaw-gateway:latest"
}

variable "domain" {
  type    = string
  default = "lab.shamsway.net"
}

variable "certresolver" {
  type    = string
  default = ""
}

variable "servicename" {
  type    = string
  default = "openclaw-gateway"
}

variable "dns" {
  type    = list(string)
  default = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}

variable "litellm_base_url" {
  description = "LiteLLM proxy base URL"
  type        = string
  default     = "https://litellm.lab.shamsway.net"
}
