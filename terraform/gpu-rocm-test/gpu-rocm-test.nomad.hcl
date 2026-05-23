# Validation job for nomad-device-amdgpu and ROCm GPU scheduling.
#
# Targets the hypervisor node (meta.hypervisor = "true"), requests 1 AMD GPU
# via the device plugin, and runs amd-smi inside a ROCm container to confirm
# device allocation, environment variable injection, and /dev/kfd visibility.
#
# Usage:
#   cd terraform/gpu-rocm-test
#   terraform init && terraform apply
#
# Check results:
#   nomad job status gpu-rocm-test
#   nomad alloc logs <alloc-id>

job "gpu-rocm-test" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "batch"

  # Pin to the hypervisor node where nomad-device-amdgpu is loaded.
  constraint {
    attribute = "$${meta.hypervisor}"
    value     = "true"
  }

  group "test" {
    count = 1

    # Do not restart on failure — this is a one-shot validation job.
    restart {
      attempts = 0
      mode     = "fail"
    }

    task "amd-smi" {
      driver = "docker"

      config {
        image              = "${image}"
        image_pull_timeout = "30m"

        # Run a sequence of amd-smi commands that together confirm:
        #   1. GPU is visible inside the container (/dev/kfd reachable via ROCm)
        #   2. ROCR_VISIBLE_DEVICES / HIP_VISIBLE_DEVICES are correctly injected
        #   3. HBM memory, PCIe, and driver metadata are accessible
        command = "/bin/bash"
        args    = ["-c", "echo '=== Allocated GPU env vars ===' && env | grep -E 'ROCR_VISIBLE|HIP_VISIBLE|GPU_DEVICE' | sort && echo '=== amd-smi list ===' && amd-smi list && echo '=== amd-smi metric ===' && amd-smi metric && echo '=== PASS ==='"]

        # ROCm IPC: amd-smi communicates with the GPU driver via shared memory
        # segments in the host IPC namespace.
        ipc_mode = "host"

        # amd-smi issues syscalls (e.g. perf_event_open) blocked by Docker's
        # default seccomp profile.
        security_opt = ["seccomp=unconfined"]
      }

      resources {
        cpu    = 1000
        memory = 4096

        # Request 1 GPU from nomad-device-amdgpu.
        # The plugin will inject ROCR_VISIBLE_DEVICES, HIP_VISIBLE_DEVICES,
        # GPU_DEVICE_ORDINAL and mount /dev/kfd + /dev/dri/renderD* + /dev/dri/card*.
        device "amd/gpu" {
          count = 1
        }
      }
    }
  }
}
