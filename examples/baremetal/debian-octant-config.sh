#!/bin/bash
## Install needed packages and repos

apt-get update
apt-get -y upgrade
apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg2 \
  lsb-release \
  software-properties-common

curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"

curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | sudo apt-key add -
apt-add-repository "deb https://pkgs.tailscale.com/stable/debian $(lsb_release -cs) main"

apt-get update

apt-get install -y \
  cloud-init \
  cloud-initramfs-growroot \
  jq \
  grc \
  git \
  tmux \
  htop \
  unzip \
  pydf \
  yafc \
  nfs-kernel-server \
  ntp \
  frr \
  curl \
  wget \
  rsync \
  netcat-traditional \
  dnsmasq \
  mtr-tiny \
  speedometer \
  bridge-utils \
  acl \
  build-essential \
  automake \
  autoconf \
  dnsmasq \
  systemd-container \
  net-tools \
  bind9-dnsutils \
  man \
  golang \
  podman \
  podman-compose \
  crun \
  cockpit \
  cockpit-podman \
  cockpit-pcp \
  cockpit-doc \
  open-vm-tools

##
## Debian Settings
## Misc configuration
##

echo '> SSH directory'
mkdir -vp $HOME/.ssh

## Set banners

cat > /etc/issue << EOL
       ::::::::   :::::::: ::::::::::: :::     ::::    ::: ::::::::::: 
    :+:    :+: :+:    :+:    :+:   :+: :+:   :+:+:   :+:     :+:      
   +:+    +:+ +:+           +:+  +:+   +:+  :+:+:+  +:+     +:+       
  +#+    +:+ +#+           +#+ +#++:++#++: +#+ +:+ +#+     +#+        
 +#+    +#+ +#+           +#+ +#+     +#+ +#+  +#+#+#     +#+         
#+#    #+# #+#    #+#    #+# #+#     #+# #+#   #+#+#     #+#          
########   ########     ### ###     ### ###    ####     ###    
EOL
echo "Debian $(cat /etc/debian_version)" | tee -a /etc/issue > /dev/null

cat > /etc/issue.net << EOL
   _ \   __| __ __|  \     \ | __ __| 
  (   | (       |   _ \   .  |    |   
 \___/ \___|   _| _/  _\ _|\_|   _|   
EOL
                                                                
## Prep cloud-init

cp /etc/systemd/cloud-init/cloud-init.cfg /etc/cloud/
cp /etc/systemd/cloud-init/datasource.cfg.d/10_datasource.cfg /etc/cloud/cloud.cfg.d/
sudo cloud-init clean --logs



## Enable rc.local

echo '> Enable rc.local'
cat << EOF > /etc/rc.local
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

if [ ! -f /etc/debian.config ]; then
    #/sbin/debian-init.py
    echo "\$(date)" > /etc/debian.config
    #touch /etc/cloud/cloud-init.disabled
fi

exit 0
EOF
chmod +x /etc/rc.local
systemctl daemon-reload

## Update Grub
sed -i 's/#GRUB_GFXMODE=640x480/GRUB_GFXMODE=1280x1024x8/' /etc/default/grub
update-grub

echo '> Done'