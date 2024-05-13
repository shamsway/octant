# Samba Container

The goal: share local path over SMB via container.

Example:
`podman run --name samba --publish 10445:445 --volume=/mnt/services/library:/library:Z --rm  quay.io/samba.org/samba-server:latest`

## Changing the configuration

The behavior of the container can be changed by invoking it with specific arguments for the samba-container script and/or setting environment variables.

You can include a custom configuration via the following method:

```bash
$EDITOR /path/to/config/config.json
podman run --name samba  --publish 10445:445 --volume=/path/on/host/to/share:/share:Z --volume=/path/to/config:/etc/samba-container -e SAMBACC_CONFIG=/etc/samba-container/config.json -e SAMBA_CONTAINER_ID=myid  --rm  quay.io/samba.org/samba-server:latest
```

##

```bash
[root@307f6fa3adde /]# cat /etc/passwd
root:x:0:0:Super User:/root:/bin/bash
sambauser:x:1000:1000::/invalid:/bin/false
otheruser:x:1001:1001::/invalid:/bin/false

[root@307f6fa3adde /]# cat /etc/group
root:x:0:
sambauser:x:1000:
otheruser:x:1001:
```