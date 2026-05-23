# gpu-pytorch-test

One-shot Nomad batch job that validates PyTorch + ROCm GPU scheduling on the
hypervisor node via `nomad-device-amdgpu`.

## What it tests

1. **Device allocation** — Nomad schedules the job on the hypervisor node and the
   `amd/gpu` device plugin reserves one GPU.
2. **HIP runtime init** — `torch.cuda.is_available()` returns `True`, confirming
   the ROCm/HIP userspace stack can reach the allocated GPU.
3. **Device enumeration** — `torch.cuda.device_count()` = 1 and
   `get_device_name(0)` returns the GPU product name.
4. **Tensor compute** — a 512×512 matmul executes on `cuda:0` without error.

## Prerequisites

Same as `gpu-rocm-test`:
- Hypervisor joined to the cluster (`make join-hypervisor`)
- `nomad-device-amdgpu` plugin running and GPUs fingerprinted
- Docker installed on the hypervisor

## Deployment

```bash
cd terraform/gpu-pytorch-test
terraform init
terraform apply -auto-approve
```

`rocm/pytorch:latest` is a large image (15–20 GB). First run uses
`image_pull_timeout = "60m"`. Subsequent runs use the Docker layer cache.

## Checking results

```bash
nomad job status gpu-pytorch-test

ALLOC=$(nomad job allocs gpu-pytorch-test -json | jq -r '.[0].ID')
nomad alloc logs $ALLOC
```

### Expected stdout (validated on MI300X × 8, ROCm 7.2.1, Nomad 1.11.3)

```
=== PyTorch + ROCm validation ===
torch version : 2.9.1+rocm7.2.1.gitff65f5bc
cuda available: True
device count  : 1
  [0] AMD Instinct MI300X
matmul result : shape=[512, 512] device=cuda:0
=== PASS ===
```

Note: `torch.cuda` maps to the HIP backend in ROCm PyTorch. "cuda" throughout
PyTorch refers to the HIP device, not NVIDIA CUDA.

## Teardown

```bash
terraform destroy -auto-approve
# Or:
nomad job stop -purge gpu-pytorch-test
```

---

## Key finding: ROCR_VISIBLE_DEVICES ordinal mismatch

### Root cause

`nomad-device-amdgpu` sets `ROCR_VISIBLE_DEVICES=N` using the **sysfs GPU
ordinal** (the index used for `/dev/dri/renderD*` numbering). The ROCr HSA
runtime does **not** interpret this value as a sysfs ordinal — it uses it as an
index into its own internal HSA agent enumeration, which is **different**.

Confirmed experimentally (ROCm 7.2.1, 8× MI300X):

```
# With ROCR_VISIBLE_DEVICES=6 (plugin-injected):
rocminfo → 2 CPU agents, 0 GPU agents
torch.cuda.is_available() → False

# With ROCR_VISIBLE_DEVICES unset:
rocminfo → 2 CPU agents + 1 GPU agent (AMD Instinct MI300X, gfx942)
torch.cuda.is_available() → True
cuda:0 → AMD Instinct MI300X
matmul → PASS
```

### Why unsetting is safe

The device plugin enforces GPU isolation by mounting **only the allocated GPU's**
`/dev/dri/renderD*` node into the container. With `ROCR_VISIBLE_DEVICES` unset,
ROCr enumerates whatever GPUs it can initialise — and it can only initialise the
one GPU whose render node is accessible. The container naturally sees exactly
1 GPU regardless of what the env vars say.

### Workaround (this job)

`local/test.sh` runs `unset ROCR_VISIBLE_DEVICES HIP_VISIBLE_DEVICES
GPU_DEVICE_ORDINAL` before invoking Python. This lets ROCr find the GPU through
the mounted render node without fighting its own indexing logic.

### Plugin fix needed

`nomad-device-amdgpu` should use the GPU's **UUID** (e.g.
`GPU-682f01373a97bc4f`) for `ROCR_VISIBLE_DEVICES` instead of the sysfs
ordinal, or stop setting `ROCR_VISIBLE_DEVICES` altogether and rely on the
render-node mount for isolation. UUID mode is supported by ROCr and is
unambiguous across enumeration schemes.

The GPU UUID is available from:
- `amd-smi list --json` (field `uuid`)
- `rocminfo` (field `Uuid` when vars are unset)
- sysfs: `/sys/class/drm/renderD<N>/device/unique_id` (as 64-bit hex)

---

## Troubleshooting

### `torch.cuda.is_available()` returns `False`

Check whether the issue is the `ROCR_VISIBLE_DEVICES` ordinal mismatch:

```bash
ALLOC=$(nomad job allocs gpu-pytorch-test -json | jq -r '.[0].ID')

# Check what vars the plugin injected and whether /dev/kfd is mounted
nomad alloc exec $ALLOC env | grep -E "ROCR|HIP|GPU_DEVICE"
nomad alloc exec $ALLOC ls -la /dev/kfd /dev/dri/

# Test rocminfo with and without the vars
nomad alloc exec $ALLOC rocminfo | grep -E "Agent|Device Type|Name"
nomad alloc exec $ALLOC bash -c \
  "unset ROCR_VISIBLE_DEVICES HIP_VISIBLE_DEVICES && rocminfo" \
  | grep -E "Agent|Device Type|Name"
```

If rocminfo shows GPUs only when the vars are unset, it's the ordinal mismatch.
The workaround (`unset` in the script) handles this.

### Job stuck in `pending`

```bash
nomad job status gpu-pytorch-test
# "Placement Failures" shows why the scheduler couldn't place it

nomad node status -verbose <hypervisor-node-id> | grep -A 10 "Device Group"
```

### OOM during matmul

The 512×512 float32 matmul uses ~1 MB of VRAM and is not the cause. Increase
`memory` in the job spec if PyTorch startup overhead hits the limit:

```hcl
resources {
  memory = 16384
  ...
}
```
