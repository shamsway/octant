# UniFI Server

**Description:** The UniFi Server is the management software for Ubiquiti's UniFi network devices.

**Use cases:**
- Manage UniFi network devices (access points, switches, security gateways)
- Monitor network performance and usage
- Configure network settings and policies

**Rootless container:** No

**URLs:** 
- https://www.ui.com/software/
- https://github.com/jacobalberty/unifi-docker

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

## Static IP

Since the unifi server typically needs to stay on a specific IP for discovery, add a constraint to the job to pin it to a specific Nomad agent.

Example

```
  constraint {
    attribute = "$${node.unique.name}"
    value = "bobby-agent-root"
  }
```

## Troubleshooting

Use these ssh options to connect to devices running insecure versions of sshd:

`ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa admin@[IP]`

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