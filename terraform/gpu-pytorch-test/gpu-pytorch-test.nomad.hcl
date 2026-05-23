# Validation job for PyTorch + ROCm GPU scheduling via nomad-device-amdgpu.
#
# Usage:
#   cd terraform/gpu-pytorch-test
#   terraform init && terraform apply
#
# Check results:
#   nomad job status gpu-pytorch-test
#   nomad alloc logs <alloc-id>

job "gpu-pytorch-test" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "batch"

  constraint {
    attribute = "$${meta.hypervisor}"
    value     = "true"
  }

  group "test" {
    count = 1

    restart {
      attempts = 0
      mode     = "fail"
    }

    task "pytorch" {
      driver = "docker"

      config {
        image              = "${image}"
        image_pull_timeout = "60m"
        command            = "/bin/bash"
        args               = ["/local/test.sh"]

        ipc_mode     = "host"
        security_opt = ["seccomp=unconfined"]
      }

      template {
        destination = "local/test.sh"
        data        = <<-EOF
#!/bin/bash
# nomad-device-amdgpu sets ROCR_VISIBLE_DEVICES to the sysfs GPU ordinal (e.g. 6).
# ROCr's HSA agent index does NOT match the sysfs ordinal — with the vars set,
# ROCr finds 0 GPU agents and torch.cuda.is_available() returns False.
# GPU isolation is already enforced by the device plugin mounting only the
# allocated GPU's /dev/dri/renderD* node, so unsetting the vars is safe:
# ROCr will enumerate exactly the one GPU whose render node is accessible.
unset ROCR_VISIBLE_DEVICES HIP_VISIBLE_DEVICES GPU_DEVICE_ORDINAL

python3 << 'PYEOF'
import torch, sys

print("=== PyTorch + ROCm validation ===")
print(f"torch version : {torch.__version__}")
print(f"cuda available: {torch.cuda.is_available()}")

if not torch.cuda.is_available():
    print("FAIL: torch.cuda.is_available() returned False")
    sys.exit(1)

n = torch.cuda.device_count()
print(f"device count  : {n}")
for i in range(n):
    print(f"  [{i}] {torch.cuda.get_device_name(i)}")

dev = torch.device("cuda:0")
a = torch.randn(512, 512, device=dev)
b = torch.randn(512, 512, device=dev)
c = torch.matmul(a, b)
print(f"matmul result : shape={list(c.shape)} device={c.device}")
print("=== PASS ===")
PYEOF
EOF
      }

      resources {
        cpu    = 2000
        memory = 8192

        device "amd/gpu" {
          count = 1
        }
      }
    }
  }
}
