# Nautobot

## Container Info

```bash
nautobot@34825d00fab4:~$ cat /etc/passwd
root:x:0:0:root:/root:/bin/bash
nautobot:x:999:999::/opt/nautobot:/bin/bash
```

## Scratch

Attempted to use this prestart task to install a plugin, but it's not working. Worth trying again later.

task "prep-nautobot" {
  driver = "podman"
  user = "nautobot"

  config {
    image = "docker.io/networktocode/nautobot"     
    entrypoint = "/bin/bash"
    args = ["-c", "pip install --user nautobot-chatops"]
  }

  lifecycle {
    hook = "prestart"
    sidecar = false
  }

  volume_mount {
    volume = "nautobot-config"
    destination = "/opt/nautobot/"
    read_only   = false
  }      
}

