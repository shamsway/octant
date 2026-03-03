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
  type    = string
  default = "ghcr.io/open-webui/open-webui:v0.5.16"
}

variable "domain" {
  type    = string
  default = "octant.local"
}

variable "certresolver" {
  type    = string
  default = ""
}

variable "servicename" {
  type    = string
  default = "chatllm"
}

variable "dns" {
  type    = list(string)
  default = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}

variable "ollama_url" {
  type    = string
  default = "http://ollama.service.consul:11434"
}

variable "webui_url" {
  type    = string
  default = "http://chatllm.octant.local"
}

variable "webui_auth" {
  type    = string
  default = "true"
}

variable "webui_name" {
  type    = string
  default = "Octant LLM Chat"
}
