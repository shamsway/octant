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

curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
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

echo " ________  ________ _________  ________  ________   _________" | tee /etc/issue /etc/issue.net > /dev/null   
echo "|\   __  \|\   ____\\___   ___\\   __  \|\   ___  \|\___   ___\" | tee -a /etc/issue /etc/issue.net > /dev/null 
echo "\ \  \|\  \ \  \___\|___ \  \_\ \  \|\  \ \  \\ \  \|___ \  \_|" | tee -a /etc/issue /etc/issue.net > /dev/null 
echo " \ \  \\\  \ \  \       \ \  \ \ \   __  \ \  \\ \  \   \ \  \" | tee -a /etc/issue /etc/issue.net > /dev/null  
echo "  \ \  \\\  \ \  \____   \ \  \ \ \  \ \  \ \  \\ \  \   \ \  \" | tee -a /etc/issue /etc/issue.net > /dev/null 
echo "   \ \_______\ \_______\  \ \__\ \ \__\ \__\ \__\\ \__\   \ \__\" | tee -a /etc/issue /etc/issue.net > /dev/null
echo "    \|_______|\|_______|   \|__|  \|__|\|__|\|__| \|__|    \|__|" | tee -a /etc/issue /etc/issue.net > /dev/null
echo "Debian $(cat /etc/debian_version)" | tee -a /etc/issue /etc/issue.net > /dev/null
                                                                
## Prep cloud-init

sudo cloud-init clean --logs
sudo cloud-init init --local
sudo cloud-init init


## Enable rc.local

echo '> Enable rc.local facility for debian-init.py'
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
    /sbin/debian-init.py
    echo "\$(date)" > /etc/debian.config
fi

exit 0
EOF
chmod +x /etc/rc.local
systemctl daemon-reload

echo '> Done'