# Installing Consul agent on Windows

- Create directory for config, certificates
- Copy agent certificates off existing server to consul config directory
- Configure firewall

```pwsh
$consulPorts = @(8500, 8501, 8502, 8503, 8600)

foreach ($port in $consulPorts) {
    New-NetFirewallRule -DisplayName "Consul Port $port" -Direction Inbound -LocalPort $port -Protocol TCP -Action Allow
    Write-Host "Firewall rule created for port $port"
}
```

- Run consul from WSL:
`consul agent -config-file=consul-agent.hcl -enable-script-checks`