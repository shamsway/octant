# Notes

// podman run --rm --name=tvheadend \
// -p 9981:9981 \
// -p 9982:9982 \
// -e PUID=2000 \
// -e PGID=2000 \
// -v /mnt/services/tvheadend/config:/config \
// -v /mnt/recordings/tvheadend/:/recordings \
// --privileged \
// lscr.io/linuxserver/tvheadend:latest

// podman run -d --name=tvheadend \
// -e PUID=2000 \
// -e PGID=2000 \
// -v /mnt/services/tvheadend/config:/config \
// -v /mnt/recordings/tvheadend/:/recordings \
// --privileged --network=host \
// lscr.io/linuxserver/tvheadend:latest
