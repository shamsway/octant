# Add a Ceph node

Disable local NFS server
sudo systemctl disable nfs-server.service
sudo systemctl mask nfs-server.service

sudo apt install ceph-common ceph-mon ceph-osd ceph-mds ceph-mgr ceph-fuse ceph-base python3-ceph ceph-mgr-dashboard cephadm

cephadm bootstrap --skip-monitoring-stack --mon-ip 192.168.252.6 --cluster-network 192.168.252.0/24 --ssh-user hashi --ssh-private-key /opt/homelab/data/home/.ssh/id_rsa --ssh-public-key /opt/homelab/data/home/.ssh/id_rsa.pub --apply-spec ceph-bootstrap.yml --allow-overwrite

sudo ceph cephadm set-user hashi

NOTE: Run systemctl stop nfs-client to temporarily disable the NFS client before bootstrapping the new node. This is to avoid the NFS client from interfering with the Ceph bootstrap process.

ceph orch host add jerry 192.168.252.6 --labels _admin
ceph orch host add bobby 192.168.252.7 --labels _admin
ceph orch host add billy 192.168.252.8 --labels _admin

## Prepare disk(s)

Based on your current configuration, you want to use `/dev/nvme0n1p5` for Ceph. Here are the updated instructions:

1. Create a new LVM physical volume (PV) on the partition:
   - Run the command `sudo pvcreate /dev/nvme0n1p5`.

2. Create a new LVM volume group (VG) for Ceph:
   - Run the command `sudo vgcreate ceph-vg /dev/nvme0n1p5` (replace `ceph-vg` with your desired volume group name).

3. Create a new LVM logical volume (LV) using all the available space in the volume group:
   - Run the command `sudo lvcreate -l 100%FREE -n ceph-lv ceph-vg` (replace `ceph-lv` with your desired logical volume name).

4. Verify the logical volume creation:
   - Run the command `sudo lvs` to list the logical volumes.
   - Ensure that the newly created logical volume is listed.

5. Deploy OSDs using `ceph orch apply`:
   - Run the command `ceph orch apply osd --all-available-devices`.
   - Ceph will automatically discover and use the available logical volume for creating OSDs.

Since you already have a partition (`/dev/nvme0n1p5`) available for Ceph, you can skip the partitioning step and directly create a physical volume (PV) on that partition using `pvcreate`.

Then, proceed with creating a volume group (VG) using the physical volume, and create a logical volume (LV) that spans all the available space in the volume group.

Finally, deploy the OSDs using `ceph orch apply osd --all-available-devices`, and Ceph will automatically use the logical volume for creating OSDs.

Remember to replace the volume group names and logical volume names with the appropriate values based on your setup.

## Configure OSDs

ceph orch apply osd --all-available-devices

or

ceph orch daemon add osd *<host>*:*<device-path>*
(see https://docs.ceph.com/en/latest/cephadm/services/osd/#cephadm-deploy-osds)

ceph orch daemon add osd bobby:/dev/ceph-vg/ceph-lv

### Updating settings for "V2P" hosts
Some fixes for things when a VM is converted to a physical host

Edit and redeploy the spec
`ceph orch apply -i ceph-osd.yml`

```
service_type: osd
service_id: nomad
service_name: osd.nomad
placement:
  hosts:
  - jerry
  - billy
spec:
  data_devices:
    paths:
    - /dev/sdb
  filter_logic: AND
  method: raw
  objectstore: bluestore
---
service_type: osd
service_id: nomad-bobby
service_name: osd.nomad-bobby
placement:
  hosts:
  - bobby
spec:
  data_devices:
    paths:
    - /dev/ceph-vg/ceph-lv
  filter_logic: AND
  method: raw
  objectstore: bluestore
```

Redeploy haproxy ingress
`ceph orch daemon redeploy haproxy.nfs.octantnfs.[hostname].[identifier]`

NOTE: Run systemctl stop nfs-client to temporarily disable the NFS client if you having issues deploying haproxy

# Maintenance

## Reboot a ceph node 

To reboot the Ceph Storage nodes, follow this process:

- Select the first Ceph Storage node to reboot and log into it.
- Disable Ceph Storage cluster rebalancing temporarily:
```
sudo ceph osd set noout
sudo ceph osd set norebalance
```

Reboot the node:
`sudo reboot`

Wait until the node boots. Log into the node and check the cluster status:
`sudo ceph -s`

Check that the pgmap reports all pgs as normal (active+clean).
Log out of the node, reboot the next node, and check its status. Repeat this process until you have rebooted all Ceph storage nodes.

When complete, enable cluster rebalancing again:
```
sudo ceph osd unset noout
sudo ceph osd unset norebalance
```

Perform a final status check to make sure the cluster reports HEALTH_OK:
`sudo ceph status`

## Put a node in maintenance mode

ceph orch host maintenance enter <hostname> --force --yes-i-really-mean-it
ceph orch host maintenance exit <hostname>
ceph orch host ok-to-stop  <hostname>

## Remove a Ceph node

Check existing specs
`ceph orch ls --export`

Check the storage cluster’s capacity:

```
ceph df
rados df
ceph osd df
```

Temporarily disable scrubbing:

```
ceph osd set noscrub
ceph osd set nodeep-scrub
```

Limit the backfill and recovery features:

```
ceph tell osd.* injectargs --osd-max-backfills 1 --osd-recovery-max-active 1 --osd-recovery-op-priority 1
```

Remove each OSD on the node from the storage cluster:

IMPORTANT: When removing an OSD node from the storage cluster, remove one OSD at a time within the node and allowing the cluster to recover to an active+clean state before proceeding to remove the next OSD.

```
ceph osd tree
ceph osd out {osd-num}
ceph osd in {osd-num} # small clusters
ceph osd crush reweight osd.{osd-num} 0 # small clusters

sudo systemctl stop ceph-osd@{osd-num}
ceph osd purge {osd-num} --yes-i-really-mean-it
```


After you remove an OSD, check to verify that the storage cluster is not getting to the near-full ratio:

```
ceph -s
ceph df
```

Repeat this step until all OSDs on the node are removed from the storage cluster.

Once all OSDs are removed, remove the host:

Log into the Cephadm shell

```
cephadm shell
```

Fetch the host details:

```
ceph orch host ls
```

Drain all the daemons from the host:

```
ceph orch host drain {hostname}

or ceph orch host maintenance enter {hostname} --force --yes-i-really-mean-it ?
```

The _no_schedule label is automatically applied to the host which blocks deployment.

Check the status of OSD removal:

```
ceph orch osd rm status
```

When no placement groups (PG) are left on the OSD, the OSD is decommissioned and removed from the storage cluster.

Check if all the daemons are removed from the storage cluster:

``
ceph orch ps [host]
```

Remove the host:

```
ceph orch host rm [host]
ceph orch host rm [host] --offline --force  # If needed
```

## Clean up

ceph mgr module disable cephadm
ceph fsid
cephadm rm-cluster --force --zap-osds --fsid [fsid]
cephadm rm-cluster --force --zap-osds --fsid 2e13015c-f0ad-11ee-8cdf-000c2961913e

sudo wipefs -f -a /dev/sdb
sgdisk --zap-all /dev/sdb

ceph osd unset noscrub
ceph osd unset nodeep-scrub

# Troubleshooting

## Time sync issues

ceph time-sync-status

ntpq -p

/etc/ntp.cfg

driftfile /var/lib/ntp/ntp.drift
statistics loopstats peerstats clockstats
filegen loopstats file loopstats type day enable
filegen peerstats file peerstats type day enable
filegen clockstats file clockstats type day enable

server 0.debian.pool.ntp.org iburst
server 1.debian.pool.ntp.org iburst
server 2.debian.pool.ntp.org iburst
server 3.debian.pool.ntp.org iburst

restrict -4 default kod notrap nomodify nopeer noquery limited
restrict -6 default kod notrap nomodify nopeer noquery limited

restrict 127.0.0.1
restrict ::1

## Host noout

ceph health detail reports "host [hostname] has flags noout"

Fix: `ceph osd unset-group noout jerry`