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

podman run -d \
  --name hashi --rm \
  -u hashi --userns="keepid:uid=31337,gid=31337" \
  -v /tmp:/tmp/xteve \
  -p 34400:34400/tcp \
  -e PUID="2000" \
  -e PGID="2000" \
  -e TZ="America/New_York" \
  fyb3roptik/threadfin

podman run -d \
  --name threadfin --rm \
  -u 2000 \
  -v /tmp:/tmp/xteve \
  -v /mnt/services/threadfin:/home/threadfin/conf \
  -p 34400:34400/tcp \
  -e PUID="2000" \
  -e PGID="2000" \
  -e TZ="America/New_York" \
  fyb3roptik/threadfin