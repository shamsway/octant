provider "nomad" {
  address = "http://${var.nomad}:4646"
}

resource "nomad_job" "vllm-gemma4-31b" {
  jobspec = templatefile("${path.module}/vllm-gemma4-31b.nomad.hcl", {
    region                = var.region
    datacenter            = var.datacenter
    image                 = var.image
    port                  = var.port
    model                 = var.model
    served_model_name     = var.served_model_name
    gpu_memory_utilization = var.gpu_memory_utilization
    max_model_len         = var.max_model_len
  })
}
