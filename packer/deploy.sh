#!/bin/bash

# Example command: ./deply.sh [rootpassword] ~/.ssh/id_rsa.pub [IP] [hostname]
# Check if all required arguments are provided
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <root_password> <ssh_key_file> <ip_address> <hostname>"
    exit 1
fi

# Assign command-line arguments to variables
root_password="$1"
ssh_key_file="$2"
ip_address="$3"
hostname="$4"

# Read SSH public key from file
ssh_key=$(cat "$ssh_key_file")

# Generate salted SHA-512 hash for root password
root_password_hash=$(perl -e 'print crypt($ARGV[0], "\$6\$rounds=4096\$jfnZvYour0otR00tPa\$") . "\n"' "$root_password")

# Construct the user-data template
user_data=$(cat <<EOF
#cloud-config

hostname: hostname

# Set the root password
ssh_passwd: $root_password_hash

# Create a new user
users:
  - name: matt
    gecos: Admin User
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    lock_passwd: false
    ssh_authorized_keys:
      - $ssh_key

# Enable root login over SSH
ssh_pwauth: true

# Configure network interface
write_files:
  - path: /etc/network/interfaces
    content: |
      auto eth0
      iface eth0 inet static
        address $ip_address
        netmask 255.255.255.0
        gateway 192.168.252.1
        dns-nameservers 192.168.252.1

runcmd:
  # Set the root password
  - echo "root:$root_password_hash" | chpasswd -e
EOF
)

# Encode the user-data as base64
user_data_base64=$(echo "$user_data" | base64)
echo "$user_data_base64" > "user-data-base64.txt"

# Print the ovftool command with the encoded user-data
echo "ovftool --noSSLVerify --overwrite --allowExtraConfig --diskMode=thin --name=\"$hostname\" --deploymentOption=\"2CPU-2GB\" --extraConfig:guestinfo.userdata=\"\$(cat user-data-base64.txt)\" --extraConfig:guestinfo.userdata.encoding=\"base64\" octantnode.ova 'vi://matt:FuckHock1!@192.168.252.5:8697'"