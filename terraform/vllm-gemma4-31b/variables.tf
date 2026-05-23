variable "nomad" {
  description = "Nomad server address (hostname or IP, no scheme or port)"
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
  description = "vLLM ROCm image with Gemma4 support"
  type        = string
  default     = "vllm/vllm-openai-rocm:gemma4"
}

variable "port" {
  description = "Host port to expose the vLLM OpenAI-compatible API on"
  type        = number
  default     = 8100
}

variable "model" {
  description = "HuggingFace model ID to serve"
  type        = string
  default     = "google/gemma-4-31B-it"
}

variable "served_model_name" {
  description = "Model name advertised via the OpenAI /v1/models endpoint"
  type        = string
  default     = "gemma-4-31b-it"
}

variable "gpu_memory_utilization" {
  description = "Fraction of GPU HBM to reserve for KV cache (0.0–1.0). Reduce to 0.85 if OOM during inference."
  type        = string
  default     = "0.90"
}

variable "max_model_len" {
  description = "Maximum sequence length (tokens). Gemma4-31B supports up to 256K; 32768 is a safe starting point."
  type        = number
  default     = 32768
}
