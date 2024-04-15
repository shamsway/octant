# Add a Ceph node
sudo apt install ceph-common ceph-mon ceph-osd ceph-mds ceph-mgr ceph-fuse ceph-base python3-ceph ceph-mgr-dashboard cephadm

cephadm bootstrap --skip-monitoring-stack --mon-ip 192.168.252.6 --cluster-network 192.168.252.0/24 --ssh-user hashi --ssh-private-key /opt/homelab/data/home/.ssh/id_rsa --ssh-public-key /opt/homelab/data/home/.ssh/id_rsa.pub --apply-spec ceph-bootstrap.yml --allow-overwrite

sudo ceph cephadm set-user hashi

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

# Remove a Ceph node

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
ceph osd purge 1 --yes-i-really-mean-it
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
ceph orch host drain host02
```

The _no_schedule label is automatically applied to the host which blocks deployment.

Check the status of OSD removal:

```
ceph orch osd rm status
```

When no placement groups (PG) are left on the OSD, the OSD is decommissioned and removed from the storage cluster.

Check if all the daemons are removed from the storage cluster:

``
ceph orch ps [host]]
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