variable "nomad" {
  description = "Nomad server address"
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
  description = "instinct-dash container image (must be pre-built and pushed to the local registry)"
  type        = string
  default     = "192.168.122.1:5000/instinct-dash:latest"
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
  default = "instinct-dash"
}

variable "dns" {
  type    = list(string)
  default = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}

variable "poll_interval_ms" {
  description = "GPU metrics and container discovery polling interval in milliseconds"
  type        = number
  default     = 5000
}
