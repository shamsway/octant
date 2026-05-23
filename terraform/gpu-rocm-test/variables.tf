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
  description = "ROCm image to test with. Must match the ROCm version installed on the hypervisor."
  type        = string
  default     = "rocm/dev-ubuntu-24.04:7.2.1"
}
