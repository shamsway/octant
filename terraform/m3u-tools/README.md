# xteve notes

podman run -d --name=xteve -p 34400:34400 -e TZ=America/New_York -v /mnt/services/iptvtools/xteve-config:/root/.xteve:rw -v /mnt/services/iptvtools/xteve-config:/config:rw alturismo/xteve