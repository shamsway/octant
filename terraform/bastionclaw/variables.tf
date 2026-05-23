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
  description = "Orchestrator container image"
  type        = string
  default     = "192.168.122.1:5000/bastionclaw:latest"
}

variable "agent_image" {
  description = "Agent container image spawned by orchestrator"
  type        = string
  default     = "192.168.122.1:5000/bastionclaw-agent:latest"
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
  default = "bastionclaw"
}

variable "dns" {
  type    = list(string)
  default = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}

variable "litellm_base_url" {
  description = "LiteLLM proxy base URL"
  type        = string
  default     = "http://litellm.service.consul:4000"
}

variable "podman_socket_path" {
  description = "Host path to rootless Podman socket (hashi user UID 2000)"
  type        = string
  default     = "/run/user/2000/podman/podman.sock"
}
