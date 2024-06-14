variable "OP_API_TOKEN" {
  description = "Auth token for 1password connect vault"
  type = string
}

variable "nomad" {
  description = "Nomad server address"
  type = string
  default = "nomad.shamsway.net"
}

variable "consul" {
  description = "Consul server address"
  type = string
  default = "consul.shamsway.net"
}

variable "region" {
  type = string
  default = "home"
}

variable "datacenter" {
  type = string
  default = "shamsway"
}

variable "image" {
  type = string
  default = "ghcr.io/open-webui/open-webui:v0.3.4"
}

variable "ollama_url" {
  type = string
  default = "http://ollama.service.consul:11434"
}

variable "webui_url" {
  type = string
  default = "https://chatllm.shamsway.net"
}

variable "webui_auth" {
  type = string
  default = "true"
}

variable "webui_name" {
  type = string
  default = "Octant LLM Chat"
}