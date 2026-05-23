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
  description = "ROCm PyTorch image. Uses latest to always pull the current release."
  type        = string
  default     = "rocm/pytorch:latest"
}
