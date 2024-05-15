# UniFI Controller

Link: https://github.com/jacobalberty/unifi-docker?tab=readme-ov-file#environment-variables
Alternate Link: https://github.com/linuxserver/docker-unifi-network-application

## Traefik Config

linuxserver/docker-unifi-network-application uses a self-signed certificate by default. This means the scheme is https. To use a reverse proxy like Traefik, follow these steps:

- Create a ServerTransport in your dynamic Traefik configuration; in this example, `ignorecert`.

```
http:
    serversTransports:
    ignorecert:
        insecureSkipVerify: true
```

- Then on our unifi service we tell it to use this rule, as well as telling Traefik the backend is running on https.

    - traefik.http.services.unifi.loadbalancer.serverstransport=ignorecert
    - traefik.http.services.unifi.loadbalancer.server.scheme=https

# Podman commands

## Unifi

### jacobalberty/unifi-docker/ image

```bash
podman run --rm --name unifi --user unifi \
  -p 8443:8443 \
  -p 3478:3478/udp \
  -p 10001:10001/udp \
  -p 8081:8081 \
  -p 1900:1900/udp \
  -p 8843:8843 \
  -p 8880:8880 \
  -p 5514:5514/udp \
  -e TZ=Amercica/New_York \
  -e UNIFI_HTTP_PORT=8081 \
  -e UNIFI_HTTPS_PORT=8443 \
  -e UNIFI_STDOUT=true \
 docker.io/jacobalberty/unifi:6.0.43
  ```

#### Container info

With `--user unifi`
```bash
unifi@63060995483b:/unifi$ whoami
unifi
unifi@63060995483b:/unifi$ id -u
999
unifi@63060995483b:/unifi$ id -g
999
root@1a80ba529ca4:/unifi# cat /etc/passwd
root:x:0:0:root:/root:/bin/bash
unifi:x:999:999::/home/unifi:/bin/sh
mongodb:x:101:102::/var/lib/mongodb:/usr/sbin/nologin
```

Running withiout `--user unifi`
```bash
root@1a80ba529ca4:/unifi# id -u
0
root@1a80ba529ca4:/unifi# id -g
0
```

### linuxserver image info (not used)

Host networking

```bash
podman run -d --rm --name unifi \
  --network=host \
  -e PUID=2000 \
  -e PGID=2000 \
  -e TZ=Amercica/New_York \
  -e MONGO_USER=unifi \
  -e MONGO_PASS=M0ng0DB1! \
  -e MONGO_HOST=192.168.252.6 \
  -e MONGO_PORT=27017 \
  -e MONGO_DBNAME=unifi \
 lscr.io/linuxserver/unifi-network-application:7.5.176
```

Rootless/userspace networking

```bash
podman run --rm --name unifi \
  -p 8443:8443 \
  -p 3478:3478/udp \
  -p 10001:10001/udp \
  -p 8081:8080 \
  -p 1900:1900/udp \
  -p 8843:8843 \
  -p 8880:8880 \
  -p 5514:5514/udp \
  -e TZ=Amercica/New_York \
  -e MONGO_USER=unifi \
  -e MONGO_PASS=M0ng0DB1! \
  -e MONGO_HOST=192.168.252.6 \
  -e MONGO_PORT=27017 \
  -e MONGO_DBNAME=unifi \
 lscr.io/linuxserver/unifi-network-application:7.5.176
  ```

#### Container info

```bash
root@5b76cdd788fa:/usr/lib/unifi# id -u
0
root@5b76cdd788fa:/usr/lib/unifi# id -g
0
root@5b76cdd788fa:/usr/lib/unifi# cat /etc/passwd
root:x:0:0:root:/root:/bin/bash
unifi:x:101:102::/var/lib/unifi:/usr/sbin/nologin
```
### Mongo DB (required for linuxserver container version)

Create the volumes

`podman volume create mongo`

Run the MongoDB container

```bash
podman run -d --rm --name mongo \
  -p 27017:27017 \
  -e MONGO_INITDB_ROOT_USERNAME=root \
  -e MONGO_INITDB_ROOT_PASSWORD=M0ng0DB1! \
  -e MONGO_INITDB_DATABASE=unifi \
  -v ./init-mongo.js:/docker-entrypoint-initdb.d/init-mongo.js \
  mongo
```

#### Mongo DB setup

Sample `init-mongo.js` file:

```js
db.getSiblingDB("unifi").createUser({user: "unifi", pwd: "M0ng0DB1!", roles: [{role: "dbOwner", db: "unifi"}]});
db.getSiblingDB("unifi_stat").createUser({user: "unifi", pwd: "M0ng0DB1!", roles: [{role: "dbOwner", db: "unifi_stat"}]});
```

### Container info

```bash
root@5c5288b69b57:/# id -u
0
root@5c5288b69b57:/# id -g
0
root@5c5288b69b57:/# cat /etc/passwd
root:x:0:0:root:/root:/bin/bash
...
mongodb:x:999:999::/data/db:/bin/sh
```
