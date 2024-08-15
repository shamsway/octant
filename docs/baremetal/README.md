# Using Packer files for bare metal installs

- Download the Debian network installation ISO and create a bootable USB with https://rufus.ie/en/
- Adjust the preseed.cfg file for the server you are installing. 
  - Items to change are the disk partitioning and grub config. 
  - The example in this folder will allocate 100 GB on /dev/nvme01p1 for boot/swap/user partitions, and leave the rest unpartitioned.
- Copy preseed.cfg to the root of your USB drive.
- Edit grub.cfg in /boot/grub/grub.cfg
  - Edit the installer option (or copy/paste the installer option to create 'automated installer'). Add these options to the end of the 'linux' line:
  - 'auto file:///cdrom/preseed.cfg interface=eth0 netcfg/choose_interface=eth0 net.ifnames=0'
- Run `packer build` to create a VM template
- Deploy the VM, log in as root and authenticate to 1Password
- Run the Ansible playbook to perform VM customization (hostname, network config, user accounts, install required packages, etc.)

# Adding nodes

- Install using prepared USB drive
- Run cloud-init
- Verify networking / configure as needed
- Add requirements role
  - `ansible-playbook homelab.yml -i inventory/groups.yml -l [host] --tags "requirements"`
- Install Ceph dependencies (add this to preseed.cfg or debian-octant-config.sh)
- Add ceph node
- Add ceph OSD
- Configure mount points and any other desired storage config
  - `/mnt/servces` is should be mounted and accessable by all hosts. This can be a distributed `cephfs` filesystem, an NFS-based NAS volume, or any other workable shared storage.
- Add consul role
  - `ansible-playbook homelab.yml -i inventory/groups.yml -l [host] --tags "consul"`
- Add nomad role
  - `ansible-playbook homelab.yml -i inventory/groups.yml -l [host] --tags "consul"`
- Join the Nomad cluster
  - `nomad server join "[first host]:4648"`
- Clean up old data
  - `nomad system gc`
- Add restic role
  - `ansible-playbook homelab.yml -i inventory/groups.yml -l [host] --tags "restic"` 
  - repo must be initialized before first use: `restic -r s3:[url]/[bucket] init`

## Linux briding config

sudo apt install bridge-utils
sudo brctl addbr br0
sudo brctl addif br0 eth2
sudo brctl addif br0 eth3
sudo ifconfig br0 192.168.230.1 netmask 255.255.255.0 up

(?)
sudo ifconfig eth0 0.0.0.0 up
sudo ifconfig eth1 0.0.0.0 up

### Persistent config
# /etc/network/interfaces.d/br0.cfg
auto br0
iface br0 inet static
    address 192.168.230.1
    netmask 255.255.255.0
    bridge_ports eth2 eth3
    bridge_stp off
    bridge_fd 0

# Node maintenance

## Drain Nomad Jobs

`nomad node drain -self -enable -force -m "node maintenance" -yes`