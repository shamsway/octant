# Using Packer files for bare metal installs

- Download the Debian network installation ISO and create a bootable USB with https://rufus.ie/en/
- Adjust the preseed.cfg file for the server you are installing. 
  - Items to change are the disk partitioning and grub config. 
  - The example in this folder will allocate 100 GB on /dev/nvme01p1 for boot/swap/user partitions, and leave the rest unpartitioned. 'debian-octant-config.sh' will run on first boot, perform some additional config and stage the cloud-init files.
- Copy preseed.cfg to the root of your USB drive.
- Copy cloud-init.cfg, debian-init.py and any other files/scripts you want to run to files/ in the root of your USB drive.
- Edit grub.cfg in /boot/grub/grub.cfg
  - Edit the installer option (or copy/paste the installer option to create 'automated installer'). Add these options to the end of the 'linux' line:
  - 'auto file:///cdrom/preseed.cfg interface=eth0 netcfg/choose_interface=eth0 net.ifnames=0'