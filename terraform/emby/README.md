# Emby Server

## Podman command

podman run -d --name embyserver \
  --network host \
  --env UID=2000 \
  --env GID=2000 \
  --env GIDLIST=100 \
  --volume /path/to/programdata:/config \
  --volume /path/to/tvshows:/mnt/share1 \
  --volume /path/to/movies:/mnt/share2 \
  --device /dev/dri:/dev/dri \
  --device /dev/vchiq:/dev/vchiq \
  emby/embyserver