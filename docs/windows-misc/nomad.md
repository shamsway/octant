# Installing Nomad agent on Windows

- Create directory for config, certificates
- Copy agent certificates off existing server to consul config directory
- Create inbound firewall rules

```pwsh
$nomadPorts = @(4646, 4647, 4648)

foreach ($port in $nomadPorts) {
    New-NetFirewallRule -DisplayName "Nomad Port $port" -Direction Inbound -LocalPort $port -Protocol TCP -Action Allow
    Write-Host "Firewall rule created for port $port"
}
```

- Download nomad nvidia plugin
```bash
mkdir /mnt/h/hashi/nomad/data/plugins
wget https://releases.hashicorp.com/nomad-device-nvidia/1.0.0/nomad-device-nvidia_1.0.0_linux_amd64.zip
unzip nomad-device-nvidia_1.0.0_linux_amd64.zip
mv nomad-device-nvidia /mnt/h/hashi/nomad/data/nomad-agent/plugins
```

- If the plugin doesn't work, delete it and compile with the newest version of go-nvml

Install golang (https://go.dev/doc/install)
```bash
wget https://go.dev/dl/go1.22.3.linux-amd64.tar.gz
rm -rf /usr/local/go && rm -rf /usr/bin/go && tar -C /usr/local -xzf go1.22.3.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile

```

Download plugin
```bash
git clone https://github.com/hashicorp/nomad-device-nvidia
```

Edit `go.mod` and update version of go-nvml used to the latest version. Check https://github.com/NVIDIA/go-nvml/tags for the latest release.
```bash
github.com/NVIDIA/go-nvml v0.12.0-6
```

Build and install the plugin
```bash
go get github.com/hashicorp/nomad-device-nvidia/nvml
go get github.com/Masterminds/sprig/v3@v3.2.3
go get github.com/hashicorp/raft-autopilot@v0.2.0
go get github.com/hashicorp/nomad/helper/pluginutils/hclutils@v1.7.6
make test
make pkg/linux_amd64/nomad-device-nvidia
cp pkg/linux_amd64/nomad-device-nvidia /mnt/h/hashi/nomad/data/nomad-agent/plugins/
```

- Configure nomad nvidia plugin: https://developer.hashicorp.com/nomad/plugins/devices/nvidia. Example config:
```hcl
plugin "nomad-device-nvidia" {
  config {
    enabled            = true
    fingerprint_period = "1m"
  }
}
```
- Run (or restart) nomad from WSL:
`nomad agent -config=/mnt/h/hashi/nomad/nomad-agent.hcl &`