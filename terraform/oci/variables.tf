variable "tenancy_ocid" {
  description = "The OCID of the tenancy."
  type        = string
}

variable "user_ocid" {
  description = "The OCID of the user."
  type        = string
}

variable "fingerprint" {
  description = "The fingerprint of the API key."
  type        = string
}

variable "private_key_path" {
  description = "The path to the private key file."
  type        = string
}

variable "region" {
  description = "The region to deploy resources in."
  type        = string
  default     = "us-ashburn-1"
}

# variable "compartment_ocid" {
#   description = "The OCID of the compartment to deploy resources in."
#   type        = string
# }

variable "amd_instance_count" {
  description = "The number of Always Free AMD-based compute VMs to create."
  type        = number
  default     = 2
}

variable "amd_instance_shape" {
  description = "The shape of the Always Free AMD-based compute VMs."
  type        = string
  default     = "VM.Standard.E2.1.Micro"
}

variable "arm_instance_ocpus" {
  description = "The number of OCPUs for the Always Free Arm-based Ampere A1 VM."
  type        = number
  default     = 1
}

variable "arm_instance_memory_in_gbs" {
  description = "The amount of memory (in GB) for the Always Free Arm-based Ampere A1 VM."
  type        = number
  default     = 6
}

variable "vcn_cidr_block" {
  description = "The CIDR block for the Virtual Cloud Network (VCN)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr_block" {
  description = "The CIDR block for the subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "local_ip" {
  description = "IP to use for SSH ACL in CIDR Format (1.2.3.4/32). Use `curl http://icanhazip.com` to get your public IP"
  type        = string
}

variable "admin_user" {
  description = "Local admin user"
  type        = string
  default = "matt"
}

variable "ssh_public_key" {
  description = "SSH public key to add to authorized keys"
  type        = string
  default = "~/.ssh/id_rsa.pub"
}