# Notes and Runbooks

## Troubleshooting

### Nomad Job Failures

**Symptom:** Job shows `pending` or `failed` in Nomad UI.

1. Check the allocation status:
   ```bash
   nomad job status <job-name>
   ```
2. View allocation logs:
   ```bash
   nomad alloc logs <alloc-id>
   ```
3. Common causes:
   - **Port conflict:** Another allocation is using the same port. Check with `nomad alloc status`.
   - **Image pull failure:** Verify the image name and tag. Check Podman connectivity to the registry.
   - **Volume mount error:** Ensure host volume directories exist (`make deploy-volumes`).
   - **Resource constraints:** Node may be out of memory or CPU. Check `nomad node status`.

### Consul Cluster Issues

**Symptom:** Services not resolving, Consul UI unreachable.

1. Check Consul member status:
   ```bash
   consul members
   ```
2. Verify leader election:
   ```bash
   consul operator raft list-peers
   ```
3. If a node is `left` or `failed`:
   ```bash
   make start-consul-host HOST=<node>
   ```
4. For a full reset (destroys all Consul data):
   ```bash
   make reset-consul
   ```

### Ceph Health Warnings

**Symptom:** `ceph health` reports `HEALTH_WARN` or `HEALTH_ERR`.

1. Check cluster status:
   ```bash
   ceph status
   ceph health detail
   ```
2. Check OSD status:
   ```bash
   ceph osd tree
   ```
3. Common warnings:
   - **`too few PGs per OSD`:** Expected in a small cluster; can be adjusted with `ceph osd pool set <pool> pg_num <num>`.
   - **`noout` flag set:** Intentional during maintenance; clear with `ceph osd unset noout`.
   - **OSD down:** Check the node, restart with `systemctl restart ceph-osd@<id>`.

### Service Not Accessible via URL

1. Check if the Nomad job is running:
   ```bash
   nomad job status <service>
   ```
2. Check Consul service registration:
   ```bash
   consul catalog services
   consul health checks <service>
   ```
3. Check Traefik routing:
   - Visit `https://traefik.lab.shamsway.net`
   - Look for the service in the HTTP routers list
4. Check HAProxy (on the hypervisor):
   ```bash
   systemctl status haproxy
   ```

### CSI Volume Issues

**Symptom:** Allocation stays `pending` with a CSI-related error.

1. Check the CSI plugin health:
   ```bash
   nomad plugin status ceph-csi
   ```
   All 3 nodes should show as healthy. If a node is missing:
   ```bash
   nomad job eval ceph-csi-node
   ```

2. Check the volume exists and is not claimed by another allocation:
   ```bash
   nomad volume status -type=csi <volume-id>
   ```
   Look for existing claims. A `single-node-writer` volume can only be claimed
   by one allocation at a time.

3. If the allocation is stuck after `nomad job stop` + `terraform apply`:
   ```bash
   # terraform sees "no changes" because the jobspec didn't change
   terraform taint nomad_job.<service>
   terraform apply
   ```

4. If the volume needs manual inspection:
   ```bash
   # List RBD images in the CSI pool
   ssh octant-01 'sudo rbd ls nomad-csi'

   # Check which RBD images are currently mapped to devices
   ssh octant-01 'sudo rbd device list'

   # Get details on a specific image
   ssh octant-01 'sudo rbd info nomad-csi/<image-name>'
   ```

**Symptom:** Application fails with permission errors on CSI volume.

The ext4 filesystem root is owned by `root:root`. Every CSI-backed service
needs a `volume-init` prestart task to `chown` the mount to the app's UID:

```bash
# Find the app's UID inside the container
nomad alloc exec -task <service> <alloc-id> id
```

Then add/fix the volume-init task in the job spec.

**Symptom:** Application rejects files as "bad file" or "invalid filesystem."

Some applications (e.g., MongoDB 8) reject files on non-standard filesystems
like CephFS, tmpfs, or overlay. CSI RBD volumes use ext4, which solves this.
If the app still complains, ensure the file is on the CSI volume path, not in
Nomad's `local/` alloc directory (which is tmpfs/overlay).

**Symptom:** `nomad volume create` fails.

- Check Ceph cluster health: `ceph status`
- Verify the `nomad-csi` pool exists: `ceph osd pool ls`
- Verify the `nomad-csi` user has access: `ceph auth get client.nomad-csi`
- Check if the volume ID already exists: `nomad volume status -type=csi`

### Manual RBD Volume Recovery

If you need to access data on a CSI volume while the Nomad job is stopped
(e.g., for manual restore or inspection):

```bash
# 1. Find the RBD image name from the volume ID
nomad volume status -type=csi <volume-id>
# Look for the "External ID" field — it contains the RBD image name

# 2. Map and mount on a cluster node
ssh octant-01 'sudo rbd map nomad-csi/<image-name>'
# Returns /dev/rbdN
ssh octant-01 'sudo mkdir -p /tmp/volume-recovery && sudo mount /dev/rbdN /tmp/volume-recovery'

# 3. Inspect or modify data
ssh octant-01 'ls -la /tmp/volume-recovery/'

# 4. Clean up before restarting the job
ssh octant-01 'sudo umount /tmp/volume-recovery && sudo rmdir /tmp/volume-recovery && sudo rbd unmap /dev/rbdN'
```

## Maintenance

### Updating a Service Image

1. Edit the image tag in `terraform/<service>/<service>.nomad.hcl`
2. Apply the change:
   ```bash
   cd terraform/<service> && terraform apply
   ```
3. Verify the new version is running:
   ```bash
   nomad job status <service>
   ```

### Rotating Secrets

1. Update the secret in 1Password
2. Run `direnv allow` to reload environment variables
3. Redeploy the affected service:
   ```bash
   cd terraform/<service> && terraform apply
   ```

### Rolling Node Maintenance

Use this procedure when a node needs to be rebooted for any reason: kernel
upgrades, VM resource changes, Nomad/Consul/Podman/Ceph upgrades, security
patches, or hardware maintenance. Process one node at a time to maintain
cluster availability.

Each node runs two Nomad client agents (`<node>-agent` for rootless and
`<node>-agent-root` for privileged workloads) plus a Nomad server and Consul
server. All must be drained and stopped in the correct order.

**1. Identify the node's Nomad agent IDs:**

```bash
nomad node status -short | grep <node>
```

This returns IDs for both the rootless and root agents.

**2. Mark agents as ineligible (prevents new allocations):**

```bash
nomad node eligibility -disable <agent-id>
nomad node eligibility -disable <agent-root-id>
```

**3. Drain agents (migrates running allocations to other nodes):**

```bash
nomad node drain -enable -yes -detach <agent-id>
nomad node drain -enable -yes -detach <agent-root-id>
```

Verify drains complete:

```bash
nomad node status <agent-id> | grep Drain
```

Wait until `Node drain complete` appears in the node events.

**4. Stop Nomad services (agents first, then server):**

```bash
ssh admin@<node-ip> "sudo systemctl stop nomad-agent"
ssh admin@<node-ip> "sudo systemctl stop nomad-agent-root"
ssh admin@<node-ip> "sudo systemctl stop nomad-server"
```

**5. Stop Consul services (agents first, then server):**

```bash
ssh admin@<node-ip> "sudo systemctl stop consul-agent"
ssh admin@<node-ip> "sudo systemctl stop consul-agent-root"
ssh admin@<node-ip> "sudo systemctl stop consul-server"
```

**6. Perform the maintenance:**

This is the step that varies by use case:

- **Kernel/security patches:** `ssh admin@<node-ip> "sudo apt update && sudo apt upgrade -y && sudo reboot"`
- **VM resource changes:** `virsh shutdown <node>`, modify domain XML, `virsh start <node>`
- **Nomad/Consul upgrades:** Update packages on the node, then reboot
- **Simple reboot:** `virsh shutdown <node>` then `virsh start <node>`

**7. Verify the node is back and services are running:**

```bash
ssh admin@<node-ip> "free -h && nproc"
ssh admin@<node-ip> "systemctl is-active consul-server consul-agent consul-agent-root nomad-server nomad-agent nomad-agent-root"
```

All 6 services should report `active` (they are enabled for automatic start on boot).

**8. Re-enable Nomad scheduling:**

```bash
nomad node eligibility -enable <agent-id>
nomad node eligibility -enable <agent-root-id>
```

**9. Verify cluster health before proceeding to the next node:**

```bash
consul members
nomad node status -short
ceph status
```

Confirm all members are `alive`/`ready`, Ceph is `HEALTH_OK`, and allocations
are scheduling on the node before repeating for the next node.

### Rebuilding a Node

If a single node needs to be rebuilt:

1. Drain the node in Nomad (moves jobs to other nodes):
   ```bash
   nomad node drain -enable <node-id>
   ```
2. Set Ceph `noout` flag to prevent rebalancing:
   ```bash
   ceph osd set noout
   ```
3. Tear down and reprovision the VM
4. Rejoin Consul and Nomad:
   ```bash
   make deploy-host HOST=<node>
   ```
5. Clear Ceph flag:
   ```bash
   ceph osd unset noout
   ```
6. Undrain the node:
   ```bash
   nomad node drain -disable <node-id>
   ```

### Capturing Cluster State

```bash
make capture-state
```

This runs `playbooks/07-capture-state.yml` and produces:
- `docs/state/lab-state.json` — machine-readable state
- `docs/state/lab-state.md` — human-readable markdown with version info, job status, and image drift detection

## Backup and Restore

### PostgreSQL Backup

The `postgres-backup` periodic job runs daily and stores backups at
`/mnt/services/backups/postgres/`.

Manual backup:
```bash
nomad job dispatch postgres-backup
```

### MariaDB Backup

The `mariadb-backup` periodic job runs daily and stores backups at
`/mnt/services/backups/mariadb/`.

### Restic Snapshots

The `restic-backup` periodic job creates snapshots of volumes with `backup: true`
(configured in `inventory/groups.yml`). Snapshots are stored at
`/mnt/services/backups/snapshots/`.

List snapshots:
```bash
restic -r /mnt/services/backups/snapshots snapshots
```

### Full Cluster Rebuild

To tear down and rebuild everything from scratch:

```bash
make rebuild-clean
```

This clears secrets, destroys all VMs, and runs a full deployment.
