# vLLM inference service — google/gemma-4-31B-it
#
# Dense VLM: 31B params, BF16 (~62 GB), fits on 1× MI300X (192 GB HBM3).
# Architecture: Gemma4ForConditionalGeneration (vision + text, 60 layers)
# Attention: sliding_window=1024 for 50/60 layers + full_attention for 10/60 layers
# Context: max-model-len=32768 (increase conservatively; 256K theoretical max)
#
# Usage:
#   cd terraform/vllm-gemma4-31b
#   terraform init && terraform apply
#
# Check status:
#   nomad job status vllm-gemma4-31b
#   ALLOC=$(nomad job allocs vllm-gemma4-31b -json | jq -r '.[0].ID')
#   nomad alloc logs -f $ALLOC
#   nomad alloc logs -f $ALLOC -stderr

job "vllm-gemma4-31b" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  # Pin to the hypervisor node where nomad-device-amdgpu is loaded.
  constraint {
    attribute = "$${meta.hypervisor}"
    value     = "true"
  }

  group "inference" {
    count = 1

    restart {
      attempts = 3
      delay    = "15s"
      interval = "5m"
      mode     = "delay"
    }

    network {
      port "http" {
        static = ${port}
      }
    }

    task "vllm" {
      driver = "docker"

      config {
        image              = "${image}"
        image_pull_timeout = "60m"

        # Override the image's ENTRYPOINT (the vllm CLI) to run our wrapper script,
        # which unsets ROCR_VISIBLE_DEVICES before exec'ing vLLM. Mirrors what the
        # docker-compose file does with `entrypoint: ["python3", "-m", ...]`.
        entrypoint = ["/bin/bash", "/local/run.sh"]

        ports = ["http"]

        volumes = [
          "/data/hf_home:/root/.cache/huggingface",
        ]

        # ROCm requires host IPC namespace for GPU driver communication.
        ipc_mode = "host"

        # amd-smi and ROCm issue syscalls (e.g. perf_event_open) blocked by
        # Docker's default seccomp profile.
        security_opt = ["seccomp=unconfined"]
      }

      # nomad-device-amdgpu injects ROCR_VISIBLE_DEVICES with the sysfs GPU
      # ordinal (e.g. 6). ROCr's HSA agent enumeration uses its own index that
      # does NOT match the sysfs ordinal — with the var set, ROCr finds 0 GPU
      # agents and vLLM fails with "device_count() == 0". Setting ROCR_VISIBLE_DEVICES
      # to "" in env{} does NOT work; the var must be fully unset via shell.
      # GPU isolation is enforced by the device plugin mounting only the allocated
      # GPU's /dev/dri/renderD* node — unsetting the vars is safe.
      template {
        destination = "local/run.sh"
        data        = <<-EOF
#!/bin/bash
set -euo pipefail

# nomad-device-amdgpu injects ROCR_VISIBLE_DEVICES with the sysfs GPU ordinal.
# ROCr's HSA agent index does NOT match — unset so ROCr enumerates via the
# mounted /dev/dri/renderD* node (exactly the allocated GPU).
unset ROCR_VISIBLE_DEVICES HIP_VISIBLE_DEVICES GPU_DEVICE_ORDINAL

echo "=========================================="
echo " vLLM pre-flight diagnostics"
echo " $(date -u)"
echo "=========================================="

echo ""
echo "--- GPU device mounts ---"
ls -la /dev/kfd /dev/dri/ 2>&1 || true

echo ""
echo "--- Relevant env vars ---"
env | grep -E "ROCR|HIP|GPU_DEVICE|HSA|AMD|TORCH|VLLM|PYTORCH|SAFETENSORS" | sort

echo ""
echo "--- rocminfo (first 60 lines) ---"
rocminfo 2>&1 | head -60 || echo "rocminfo not available"

echo ""
echo "--- amd-smi list ---"
amd-smi list 2>&1 || echo "amd-smi not available"

echo ""
echo "--- System memory ---"
free -h

echo ""
echo "--- HuggingFace cache ---"
ls /root/.cache/huggingface/hub/ 2>&1 | head -20 || echo "(empty or not mounted)"

echo ""
echo "=========================================="
echo " Starting vLLM"
echo "=========================================="

exec python3 -m vllm.entrypoints.openai.api_server \
  --model ${model} \
  --tensor-parallel-size 1 \
  --attention-backend TRITON_ATTN \
  --gpu-memory-utilization ${gpu_memory_utilization} \
  --max-model-len ${max_model_len} \
  --served-model-name ${served_model_name} \
  --trust-remote-code \
  --enforce-eager \
  --host 0.0.0.0 \
  --port $NOMAD_PORT_http
EOF
      }

      env {
        HIP_FORCE_DEV_KERNARG       = "1"
        TORCH_BLAS_PREFER_HIPBLASLT = "1"
        SAFETENSORS_FAST_GPU        = "1"
        VLLM_ROCM_USE_AITER         = "0"
        HSA_ENABLE_SDMA             = "0"
        HSA_OVERRIDE_GFX_VERSION    = "9.4.2"
        PYTORCH_ROCM_ARCH           = "gfx942"
        TOKENIZERS_PARALLELISM      = "false"
      }

      resources {
        cpu    = 4000
        memory = 65536

        # Request 1 GPU from nomad-device-amdgpu. The plugin mounts /dev/kfd and
        # the allocated GPU's /dev/dri/renderD* + /dev/dri/card* nodes.
        device "amd/gpu" {
          count = 1
        }
      }

      service {
        name     = "vllm-gemma4-31b"
        port     = "http"
        provider = "consul"

        check {
          type     = "http"
          path     = "/health"
          interval = "30s"
          timeout  = "5s"

          # Allow up to 6 min for model load before health checks matter.
          check_restart {
            limit           = 12
            grace           = "180s"
            ignore_warnings = false
          }
        }
      }
    }
  }
}
