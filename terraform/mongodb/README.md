# MongoDB 3-Node Replica Set

3-node MongoDB replica set (`rs0`) deployed on Nomad with Docker driver and CSI RBD volumes.

## Architecture

- **mongodb-1** on `octant-01-agent-root` (CSI volume `mongodb-1-data`)
- **mongodb-2** on `octant-02-agent-root` (CSI volume `mongodb-2-data`)
- **mongodb-3** on `octant-03-agent-root` (CSI volume `mongodb-3-data`)

Each instance is pinned to a specific node via `node.unique.name` constraint. Service discovery via Consul: `mongodb-1.service.consul`, `mongodb-2.service.consul`, `mongodb-3.service.consul`.

## Deployment

```bash
cd terraform/mongodb
terraform apply -auto-approve
```

After first deploy, the replica set must be initialized manually (one-time):

```bash
# Get credentials
MONGO_PASS=$(nomad var get -item root_password nomad/jobs/mongodb)

# Connect to any member
nomad alloc exec -task mongodb <alloc-id> mongosh -u admin -p "$MONGO_PASS" --authenticationDatabase admin

# Initialize the replica set
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "mongodb-1.service.consul:27017" },
    { _id: 1, host: "mongodb-2.service.consul:27017" },
    { _id: 2, host: "mongodb-3.service.consul:27017" }
  ]
})
```

## Replica Set Recovery After Container Restart

When MongoDB containers are restarted (e.g., after a cluster outage, GC kills, or `terraform taint`), the replica set may fail to elect a primary. All members will show `PrimarySteppedDown: No primary exists currently`.

### Root cause

MongoDB runs on Docker bridge networking. Each container gets an internal IP (e.g., `172.17.0.x`). The RS config uses Consul service names (`mongodb-N.service.consul:27017`) which resolve to host IPs (`192.168.122.x`). On startup, mongod resolves the RS member hostnames and compares the results against its own addresses. Since its own address is a Docker bridge IP, it can't match itself to any member and transitions to the `REMOVED` state. With all 3 members in `REMOVED`, no election can occur.

This resolves itself as long as the host:port mapping stays consistent (static port 27017 on each host). But if containers get new bridge IPs after a restart, a forced reconfig is needed.

### Symptoms

- MongoDB logs: `"This node is not a member of the config"` and `STARTUP → REMOVED` state transition
- `rs.status()` fails with `"Our replica set config is invalid or we are not a member of it"`
- Downstream services (e.g., Rocket.Chat) fail with `"Topology is closed"`

### Fix: Force RS reconfig

Connect to any member and run a forced reconfig:

```bash
MONGO_PASS=$(nomad var get -item root_password nomad/jobs/mongodb)
ALLOC=$(nomad job status mongodb-1 | grep 'run.*running' | awk '{print $1}')

nomad alloc exec -task mongodb $ALLOC mongosh -u admin -p "$MONGO_PASS" --authenticationDatabase admin --eval "
cfg = rs.conf();
cfg.members[0].host = 'mongodb-1.service.consul:27017';
cfg.members[1].host = 'mongodb-2.service.consul:27017';
cfg.members[2].host = 'mongodb-3.service.consul:27017';
cfg.version = cfg.version + 1;
rs.reconfig(cfg, {force: true});
"
```

Verify:

```bash
nomad alloc exec -task mongodb $ALLOC mongosh -u admin -p "$MONGO_PASS" --authenticationDatabase admin --eval "rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr))"
```

Expected output: one PRIMARY and two SECONDARYs.

After the RS is healthy, restart any downstream services that failed (e.g., `terraform taint` + `apply` for Rocket.Chat).

## Keyfile Auth

MongoDB uses keyfile authentication for inter-member communication. The keyfile is stored in Nomad variables (`nomad/jobs/mongodb` → `keyfile_secret`) and written to the CSI volume at `/data/db/.keyfile` by a `prestart` init task. This avoids MongoDB 8's rejection of keyfiles on non-real filesystems (CephFS, tmpfs, overlay).

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `"bad file"` on keyfile | Keyfile on non-real filesystem | Ensure prestart writes to CSI volume (ext4 on RBD) |
| All members REMOVED, no primary | Container restart changed bridge IPs | Force RS reconfig (see above) |
| `"Topology is closed"` from clients | No primary elected | Fix RS first, then restart clients |
| CSI volume mount fails | CSI node plugin unhealthy | Check `nomad plugin status ceph-csi` |
