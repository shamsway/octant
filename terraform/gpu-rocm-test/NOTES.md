# gpu-rocm-test

One-shot Nomad batch job that validates `nomad-device-amdgpu` GPU scheduling and
ROCm device visibility on the hypervisor node.

## What it tests

1. **Device allocation** — Nomad schedules the job on the hypervisor node and the
   `amd/gpu` device plugin reserves one GPU.
2. **Env var injection** — `ROCR_VISIBLE_DEVICES`, `HIP_VISIBLE_DEVICES`, and
   `GPU_DEVICE_ORDINAL` are present inside the container.
3. **Device mount** — `/dev/kfd` and `/dev/dri/renderD*` are accessible via the
   device plugin mounts (not manually specified).
4. **ROCm runtime** — `amd-smi list` and `amd-smi metric` complete without error,
   confirming the ROCm stack can enumerate and query the allocated GPU.

## Prerequisites

### Docker on the hypervisor

The `docker` driver requires Docker to be installed and running on the hypervisor:

```bash
# On the hypervisor
systemctl status docker
docker info
```

If Docker is not installed, install it and ensure the Nomad agent user can access
the Docker socket (typically via the `docker` group):

```bash
apt-get install -y docker.io
systemctl enable --now docker
```

### Hypervisor joined to cluster

The hypervisor must be running as a Nomad/Consul client node with
`nomad-device-amdgpu` loaded. Confirm with:

```bash
# From a Nomad server or local CLI pointed at the cluster
nomad node status
nomad node status -self -verbose | grep -A 20 "Device Group"
```

Expected output shows `amd/gpu/AMD Instinct ...` device groups.

## Deployment

```bash
cd terraform/gpu-rocm-test
terraform init
terraform apply -auto-approve
```

The `rocm/dev-ubuntu-24.04:7.2.1` image is ~8 GB. First run will take time to
pull; `image_pull_timeout = "30m"` covers this.

## Checking results

```bash
# Watch job status
nomad job status gpu-rocm-test

# Get allocation ID
ALLOC=$(nomad job allocs gpu-rocm-test -json | jq -r '.[0].ID')

# View stdout — look for ROCR_VISIBLE_DEVICES and amd-smi output ending in === PASS ===
nomad alloc logs $ALLOC

# View stderr for driver/device errors if the job failed
nomad alloc logs $ALLOC -stderr
```

### Expected stdout (validated on MI300X, ROCm 7.2.1)

The env vars reflect the **physical GPU ordinal** on the host (e.g. `3` if GPU index 3
was allocated). Inside the container, ROCm remaps the device so `amd-smi` always
reports it as `GPU: 0` — this is correct isolation behavior, not a bug.

```
=== Allocated GPU env vars ===
GPU_DEVICE_ORDINAL=3
HIP_VISIBLE_DEVICES=3
ROCR_VISIBLE_DEVICES=3
=== amd-smi list ===
GPU: 0
    BDF: 0000:65:00.0
    UUID: d2ff74a1-0000-1000-800b-839e0111a776
    ...
=== amd-smi metric ===
GPU: 0
    USAGE: ...
    POWER:
        SOCKET_POWER: 140 W
    TEMPERATURE:
        HOTSPOT: 37 °C
        MEM: 32 °C
    MEM_USAGE:
        TOTAL_VRAM: 196592 MB
    ...
=== PASS ===
```

## Teardown

```bash
terraform destroy -auto-approve
# Or remove the job directly:
nomad job stop -purge gpu-rocm-test
```

## Troubleshooting

### Job stuck in `pending`

The job can't be placed — either no node has `amd/gpu` devices or the constraint
isn't matching:

```bash
nomad job status gpu-rocm-test
# Look at "Placement Failures" in the output

# Verify the hypervisor node has GPU devices fingerprinted
nomad node status -verbose <node-id> | grep -A 10 "Device Group"

# Verify meta.hypervisor is set on the node
nomad node status -verbose <node-id> | grep hypervisor
```

### `amd-smi` fails / `/dev/kfd` not found

The device plugin did not mount `/dev/kfd`:

```bash
nomad alloc logs $ALLOC -stderr
# Check for "failed to reserve device" or permission errors in Nomad agent logs:
journalctl -u nomad -n 100 --no-pager | grep -i "amd\|device\|kfd"
```

### Docker not found on hypervisor

If the job fails with a driver error about Docker not being available, install
Docker on the hypervisor and restart the Nomad agent:

```bash
apt-get install -y docker.io
systemctl enable --now docker
systemctl restart nomad
```

---

## Lessons Learned (validated 2026-04-06, MI300X × 8, ROCm 7.2.1, Nomad 1.11.3)

### 1. Docker driver `logging` block — `options` is invalid

The `logging` block syntax differs between the docker and podman Nomad drivers.

**Docker driver** (this job):
```hcl
logging {
  type = "journald"
  config {
    tag = "my-job"
  }
}
```

**Podman driver** (e.g. instinct-dash):
```hcl
logging = {
  driver  = "journald"
  options = [{ "tag" = "my-job" }]
}
```

For a one-shot batch job the logging block can be omitted entirely — `nomad alloc logs`
works without it.

### 2. GPU ordinal in env vars vs. inside the container

`nomad-device-amdgpu` injects the **host-side physical ordinal** into the env vars:
```
ROCR_VISIBLE_DEVICES=3
HIP_VISIBLE_DEVICES=3
GPU_DEVICE_ORDINAL=3
```
The ROCm runtime inside the container then remaps the visible device to index `0`,
so `amd-smi` reports `GPU: 0` regardless of which physical GPU was allocated.
This is correct — it mirrors how `CUDA_VISIBLE_DEVICES` works with NVIDIA.

### 3. `ipc_mode = "host"` and `seccomp=unconfined` are both required

- `ipc_mode = "host"` — ROCm uses shared memory segments in the host IPC namespace
  for communication between the userspace runtime and the KFD kernel driver.
  Without it, `amd-smi` and ROCm runtimes may fail silently or hang.
- `seccomp=unconfined` — `amd-smi` calls `perf_event_open(2)`, which is blocked
  by Docker's default seccomp profile. The container starts but `amd-smi metric`
  returns partial or empty output without this.

Both are required for any ROCm workload launched via the Docker driver when
the device plugin is used for GPU allocation (vs. manual `/dev/kfd` bind-mounting).

### 4. `LOW_UTILIZATION_VIOLATION_STATUS: ACTIVE` is normal at idle

The `amd-smi metric` output shows all 8 XCPs reporting
`TOTAL_GFX_CLK_BELOW_HOST_LIMIT_VIOLATION_STATUS: ACTIVE` and
`LOW_UTILIZATION_VIOLATION_STATUS: ACTIVE` at 100%. This is expected — the
MI300X firmware throttles clock frequency when the GPU is idle to save power.
It is not an error condition.
