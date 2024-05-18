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