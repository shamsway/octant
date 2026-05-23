# instinct-dash Deployment Notes

The job targets the **hypervisor node** (`meta.hypervisor = "true"`) where the
MI300X GPUs and Docker daemon live. It uses the `docker` driver and mounts
`/dev/kfd` + `/dev/dri` directly so the dashboard can see **all 8 GPUs**, not
just a Nomad-allocated slice.

## Prerequisites

### 1. Build and Push the Image

The image must be built from `/home/melliott/git/instinct-dash` and pushed to
the local registry before Nomad can pull it:

```bash
cd /home/melliott/git/instinct-dash
podman build -t instinct-dash:latest .
podman tag instinct-dash:latest 192.168.122.1:5000/instinct-dash:latest
podman push 192.168.122.1:5000/instinct-dash:latest
```

### 2. Verify Docker Group GID on the Hypervisor

`group_add` includes GID `110` to grant Docker socket access. Confirm this
matches the hypervisor's docker group before deploying:

```bash
# On the hypervisor:
getent group docker | cut -d: -f3
```

If the GID differs, update `group_add = ["video", "110"]` in
`instinct-dash.nomad.hcl` to use the correct value.

### 3. Verify GPU Devices on the Hypervisor

```bash
# On the hypervisor:
ls -la /dev/kfd /dev/dri/
getent group video
```

---

## Deployment

```bash
cd terraform/instinct-dash
terraform init
terraform plan
terraform apply -auto-approve
```

---

## Verification

```bash
# Job is scheduled and running
nomad job status instinct-dash

# Allocation is healthy — look for "running" and passing health checks
nomad alloc status $(nomad job allocs instinct-dash -json | jq -r '.[0].ID')

# Tail logs
ALLOC=$(nomad job allocs instinct-dash -json | jq -r '.[0].ID')
nomad alloc logs -f $ALLOC

# API responds with GPU system info
nomad alloc exec -job instinct-dash curl -s http://localhost:3001/api/status | jq .systemInfo

# GPU metrics are present (not null/empty) — should show 8 devices
nomad alloc exec -job instinct-dash curl -s http://localhost:3001/api/gpus | jq '.devices | length'

# Traefik route is live
curl -I https://instinct-dash.octant.local/
```

---

## Troubleshooting

### Job stuck in `pending`

```bash
nomad job status instinct-dash
# Look for "Placement Failures"

# Verify the hypervisor node is registered and has meta.hypervisor=true
nomad node status -verbose | grep hypervisor
```

### GPU metrics unavailable / amd-smi fails

```bash
ALLOC=$(nomad job allocs instinct-dash -json | jq -r '.[0].ID')
nomad alloc logs $ALLOC -stderr
```

Common causes:
- `/dev/kfd` not present → check Docker driver `devices` mount and hypervisor device paths
- `seccomp=unconfined` not taking effect → confirm Docker version supports `security_opt`
- `video` group not granted → check `group_add` contains `"video"`

### Docker socket errors

```bash
ALLOC=$(nomad job allocs instinct-dash -json | jq -r '.[0].ID')
nomad alloc exec $ALLOC ls -la /var/run/docker.sock
```

If permission denied: GID `110` in `group_add` doesn't match the hypervisor's
docker group. Find the correct GID with `getent group docker | cut -d: -f3`
and update the job spec.

### Container won't start (OOM)

Increase `memory` from `512` to `768` in `resources` if OOM events appear.

---

## Rollback

```bash
terraform destroy -auto-approve
# Or stop without removing state:
nomad job stop instinct-dash
```
