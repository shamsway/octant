# Configure 'hashi' user to manage permissions /var/run/netns
```
sudo groupadd netns
sudo usermod -aG netns hashi
sudo chown root:netns /var/run/netns
sudo chmod 770 /var/run/netns

sudo visudo -f /etc/sudoers.d/nomad-netns
hashi ALL=(root) NOPASSWD: /bin/mount --make-rshared /var/run/netns
```

podman run -d \
  --name gluetun --rm \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun:/dev/net/tun \
  -v ./wg0.conf:/gluetun/wireguard/wg0.conf \
  -p 8888:8888/tcp \
  -p 8388:8388/tcp \
  -p 8388:8388/udp \
  -e VPN_SERVICE_PROVIDER="custom" \
  -e VPN_TYPE="wireguard" \
  -e WIREGUARD_IMPLEMENTATION="userspace" \
  qmcgaw/gluetun