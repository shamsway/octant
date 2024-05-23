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

Examples:
Raw disk: `ceph orch daemon add osd --method raw billy:/dev/sdb`
LVM: `ceph orch daemon add osd bobby:/dev/ceph-vg/ceph-lv`

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

If an OSD/virtual disk is on a physical SSD these commands can be used to properly classify it:

```bash
ceph osd crush rm-device-class osd.[#]
ceph osd crush set-device-class ssd osd.[#]
```

## Changing ceph pool defaults

Before the lab was completely built out, there were not 3 NVMe disks to use for ceph pools. Having one VM-based HDD caused some issues with ceph PG placement, so I used these commands to adjust the number of minimum disks from 3 to 2. The issue I needed to solve was several PG groups being undersized/not scrubbed. I didn't have to remove the HDD from the OSD pool to resolve the issue, changing `min_size` was all that was needed.

```bash
ceph config set osd osd_pool_default_size 2
ceph osd pool set .mgr size 2
ceph osd pool set rbd size 2
ceph osd pool set .nfs size 2
ceph osd pool set cephfs_data size 2
ceph osd pool set cephfs_metadata size 2

ceph config set osd osd_pool_default_min_size 2
ceph osd pool set .mgr min_size 2
ceph osd pool set rbd min_size 2
ceph osd pool set .nfs min_size 2
ceph osd pool set cephfs_data min_size 2
ceph osd pool set cephfs_metadata min_size 2
```

For upgrades/better redundancy, size can be set back to 3
```bash
ceph osd pool set cephfs_data size 3
ceph osd pool set cephfs_metadata size 3
ceph osd pool set .nfs size 3
ceph osd pool set rbd size 3
ceph osd pool set .mgr size 3
```

Danger zone:
```bash
ceph osd pool set .mgr min_size 1
ceph osd pool set rbd min_size 1
ceph osd pool set .nfs min_size 1
ceph osd pool set cephfs_data min_size 1
ceph osd pool set cephfs_metadata min_size 1

ceph osd pool set .mgr size 2
ceph osd pool set rbd size 2
ceph osd pool set .nfs size 2
ceph osd pool set cephfs_data size 2
ceph osd pool set cephfs_metadata size 2
```

Troubleshooting commands:

```bash
ceph osd df
ceph osd pool ls detail
ceph pg ls degraded
ceph pg dump_stuck
```

Links:

- https://docs.ceph.com/en/quincy/rados/operations/monitoring/
- https://docs.ceph.com/en/quincy/rados/operations/monitoring-osd-pg/
- https://docs.ceph.com/en/latest/rados/configuration/osd-config-ref/#confval-osd_scrub_during_recovery
- https://docs.ceph.com/en/latest/rados/configuration/pool-pg-config-ref/#rados-config-pool-pg-crush-ref
- https://docs.ceph.com/en/latest/rados/configuration/pool-pg-config-ref/
- https://ceph.io/geen-categorie/ceph-manually-repair-object/
- https://docs.ceph.com/en/latest/rados/troubleshooting/troubleshooting-pg/
- https://forum.proxmox.com/threads/please-help-ceph-pool-stuck-at-undersized-degraded-remapped-backfill_toofull-peered.121690/
- https://www.reddit.com/r/ceph/comments/18q5a5n/activeundersizeddegraded/
- https://www.reddit.com/r/ceph/comments/11ehf6u/pgs_stuck_in_undersized_mode_for_a_long_time/
- 

# Creating local RBDs

Create separate RBD pools for each server in the cluster.
```bash
ceph config set global mon_allow_pool_size_one true
ceph osd pool create rbd_jerry 32
ceph osd pool create rbd_bobby 32
ceph osd pool create rbd_billy 32
ceph osd pool application enable rbd_jerry rbd
ceph osd pool application enable rbd_bobby rbd
ceph osd pool application enable rbd_billy rbd
ceph osd pool set rbd_jerry size 1
ceph osd pool set rbd_bobby size 1
ceph osd pool set rbd_billy size 1
ceph osd pool set rbd_jerry min_size 1 --yes-i-really-mean-it
ceph osd pool set rbd_bobby min_size 1 --yes-i-really-mean-it
ceph osd pool set rbd_billy min_size 1 --yes-i-really-mean-it

```

On each server, create an RBD image within its respective pool. For example:
```bash
jerry$ rbd create --size 150G rbd_jerry/image_jerry
billy$ rbd create --size 150G rbd_bobby/image_bobby
bobby$ rbd create --size 150G rbd_billy/image_billy
```

On each server, map its respective RBD image to a local block device:
```bash
jerry$ sudo rbd map rbd_jerry/image_jerry
billy$ sudo rbd map rbd_bobby/image_bobby
bobby$ sudo rbd map rbd_billy/image_billy
```

On each server, format the mapped RBD image with a filesystem and mount it to a local directory:
```bash
sudo mkfs.xfs /dev/rbd0
sudo mkdir /mnt/rbd
sudo mount /dev/rbd0 /mnt/rbd
```

Edit /etc/fstab:
```bash
/dev/rbd0 /mnt/rbd xfs defaults 0 0
```
# Sharing Ceph via NFS

Set customized NFS Ganesha Configuration


The following sample config creates a single export. This export will not be managed by ceph nfs export interface:

```
EXPORT
{
    Export_Id = 1;
    Path = "/";
    Pseudo = "/nfs/services/library";
    Access_Type = RO;
    Squash = No_Root_Squash;
    SecType = "sys";
    Protocols = 4;
    Transports = "TCP";
    Tag = "library";

    CLIENT
    {
        Clients = "192.168.252.0/24";
        Access_Type = RO;
    }

    FSAL {
        Name = "CEPH";
    }
}
```

User specified in FSAL block should have proper caps for NFS-Ganesha daemons to access ceph cluster. User can be created in following way using auth get-or-create:

`ceph auth get-or-create client.<user_id> mon 'allow r' osd 'allow rw pool=.nfs namespace=<nfs_cluster_name>, allow rw tag cephfs data=<fs_name>' mds 'allow rw path=<export_path>'

Set customized NFS Ganesha Configuration:
`ceph nfs cluster config set <cluster_id> -i <config_file>`


# Maintenance

View running services:
`ceph orch ps`

Start a service. Example: mon
`ceph orch daemon start mon.[hostname]`

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

## Speeding Up Ceph Recovery and Rebalancing

If you need to speed up the recovery and rebalancing process in your Ceph cluster, especially in a home lab environment where performance is not a critical concern, you can make some temporary adjustments to prioritize the recovery process. Here are a few options:

## 1. Adjust the recovery settings

- Increase the `osd_recovery_max_active` setting to allow more concurrent recovery operations. For example:

  ```
  ceph tell osd.* injectargs '--osd-recovery-max-active 10'
  ```

- Increase the `osd_recovery_op_priority` setting to give higher priority to recovery operations compared to client operations. For example:

  ```
  ceph tell osd.* injectargs '--osd-recovery-op-priority 10'
  ```

## 2. Adjust the backfill settings

- Increase the `osd_max_backfills` setting to allow more concurrent backfill operations. For example:

  ```
  ceph tell osd.* injectargs '--osd-max-backfills 10'
  ```

- Increase the `osd_backfill_scan_min` and `osd_backfill_scan_max` settings to increase the number of objects scanned during backfill. For example:

  ```
  ceph tell osd.* injectargs '--osd-backfill-scan-min 256 --osd-backfill-scan-max 512'
  ```

## 3. Adjust the scrub settings

- Temporarily disable scrubbing to free up resources for recovery. For example:

  ```
  ceph osd set noscrub
  ceph osd set nodeep-scrub
  ```

- Remember to re-enable scrubbing after the recovery is complete:

  ```
  ceph osd unset noscrub
  ceph osd unset nodeep-scrub
  ```

## 4. Increase the number of recovery threads

- Increase the `osd_recovery_threads` setting to allow more threads for recovery operations. For example:

  ```
  ceph tell osd.* injectargs '--osd-recovery-threads 4'
  ```

## 5. Monitor the progress

- Keep an eye on the recovery progress using the `ceph -w` or `ceph status` command.
- You can also check the progress of individual PGs using the `ceph pg stat` command.

Please note that increasing these settings can put additional strain on your cluster resources, so it's important to monitor the cluster's performance and adjust the values accordingly. Once the recovery and rebalancing process is complete, you can revert these settings to their default values to avoid any long-term performance impact.

Also, keep in mind that the recovery process may take some time depending on the amount of data to be rebalanced and the available resources in your cluster. Be patient and allow the cluster to complete the recovery process.

If you encounter any issues or have further questions, don't hesitate to consult the Ceph documentation, seek guidance from the Ceph community, or reach out to Ceph support channels for assistance.

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

## Remove each OSD on the node from the storage cluster:

IMPORTANT: When removing an OSD node from the storage cluster, remove one OSD at a time within the node and allowing the cluster to recover to an active+clean state before proceeding to remove the next OSD.

```
ceph osd tree
ceph osd out {osd-num}
ceph osd in {osd-num} # small clusters
ceph osd crush reweight osd.{osd-num} 0 # small clusters
ceph orch daemon rm osd.{osd-num} --force

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

# Cleaning up PGs

To see which placement groups (PGs) need to be deep-scrubbed, you can use the following Ceph command:

```
ceph pg dump | grep "last_deep_scrub_stamp\\":0"
```

This command does the following:

1. `ceph pg dump`: Dumps the information about all PGs in the cluster.

2. `grep "last_deep_scrub_stamp\\":0"`: Filters the output to show only the PGs that have never been deep-scrubbed.

The `last_deep_scrub_stamp` attribute indicates the timestamp of the last deep scrub operation on a PG. If the value is 0, it means the PG has never been deep-scrubbed.

The output will display a list of PGs that require deep scrubbing. Each line will include the PG ID and other relevant information.

Alternatively, you can use the following command to get a summarized view of the PGs that need deep scrubbing:

```
ceph pg dump_stuck unclean
```

This command will display the "stuck" PGs that are in an inconsistent state, including those that need deep scrubbing.

Once you have identified the PGs that require deep scrubbing, you can initiate the deep scrub operation on those specific PGs using the command:

```
ceph pg deep-scrub <pg-id>
```

Replace `<pg-id>` with the ID of the PG you want to deep-scrub.

Note that deep scrubbing is a resource-intensive operation and can impact the performance of your cluster. It's recommended to perform deep scrubs during periods of low cluster usage or to stagger the deep scrubs over time to minimize the impact on production workloads.

# SMB Support

I don't know if any of this actually works. Seems like this is for a future version of Ceph.

# Sharing via SMB

Make sure samba package is installed on ceph nodes:
`apt install -y samba`

Create `smb.conf`:
```ini
[global]
workgroup = WORKGROUP
server string = Samba Server
security = user
map to guest = bad user
load printers = no

# Add the following lines to enable SMB access to the Ceph filesystem
vfs objects = ceph
ceph:config_file = /etc/ceph/ceph.conf
ceph:user_id = smb.octantsmb

# Define the SMB share similar to your NFS export
[octantsmb]
path = /
read only = no
create mask = 0777
directory mask = 0777
force user = smb.octantsmb
```
Create `smbcontainer.conf`:
```ini
samba-container-config = "v0"

# Define top level configurations
[configs.octantsmb]
globals = ["default"]
shares = ["octant"]

# Define shares
[shares.octant.options]
path = "/"
"read only" = "no"

# Define global options
[globals.default.options]
"load printers" = "no"
printing = "bsd"
"printcap name" = "/dev/null"
"disable spoolss" = "yes"
"guest ok" = "no"
security = "user"
"server min protocol" = "SMB2"

# Define users
[[users.all_entries]]
name = "octantsmb"
password = "octantsmb"
```

`ceph orch apply smb octantsmb https://web.shamsway.net/ceph/smbcontainer.conf --placement="jerry bobby billy"`

`ceph orch apply samba --placement="*" --config-file=./smb.conf`

```bash
ceph mgr module enable smb
ceph smb cluster create octantsmb user
```

Create a user and group resource for client authentication, `octantsmb-users.yml`:
```yaml
resource_type: ceph.smb.usersgroups
users_groups_id: octantsmb-users
values:
  users:
    - name: octantsmb
      password: octantsmbpassword
  groups: []
```

Apply user/group YAML config:

`ceph smb apply -i users.yaml`

Create an SMB share resource that maps to the same CephFS volume and path as your NFS export, `octantsmb-share.yml`:
```yaml
resource_type: ceph.smb.share
cluster_id: octantsmb
share_id: services
name: "Services"
cephfs:
  volume: cephfs
  path: /nfs/services
```

Apply SMB share YAML config:

`ceph smb apply -i share.yaml`

Verify:

`ceph smb share ls octantsmb`

### Optional - SMB container placement

If you want to control the placement of the Samba containers, you can update the SMB cluster resource with a placement specification. For example, to deploy the Samba containers on a specific host, you can create a YAML file named `placement.yaml` with the following content:

```yaml
resource_type: ceph.smb.cluster
cluster_id: octantsmb
placement:
  hosts:
    - samba-host.example.com
```

To deploy on mulitple hosts in a cluster:

```yaml
resource_type: ceph.smb.cluster
cluster_id: octantsmb
placement:
  count: [num] # Example: 3, for all three hosts in a typical cluster
```

Apply placement YAML config:

`ceph smb apply -i placement.yaml`

Alternatively, if you have labeled your Ceph nodes, you can use the label option to target specific nodes for the Samba containers:

```yaml
resource_type: ceph.smb.cluster
cluster_id: octantsmb
placement:
  label: samba-node
```

In this case, the Samba containers will be deployed on all Ceph nodes that have the label "samba-node".
After updating the placement configuration, apply the changes using the ceph smb apply command: `ceph smb apply -i placement.yaml`

Ceph will handle the deployment of the Samba containers across the specified nodes, ensuring high availability for your SMB share.

Keep in mind that the client access to the SMB share will be load-balanced across the available Samba containers. Clients can use the same SMB share path (\\<shostname>\Services) to access the share, and Ceph will automatically distribute the connections among the available containers.

By distributing the Samba containers across multiple nodes, you can achieve high availability and fault tolerance for your SMB share. If one node or container fails, the clients can still access the share through the remaining containers on the other nodes.

## ?

`ceph smb cluster create octantsmb user`

`ceph smb share create octantsmb services cephfs /`