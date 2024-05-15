# Configue wget proxy settings for downloads

```bash
export http_proxy="http://192.168.252.7:8888"
export https_proxy="https://192.168.252.7:8888"
```

# Notes
- Public IP API: http://[gluetun:port]/v1/publicip/ip

# Troubleshooting

- Issue: Web interface does not start. Fix: remove .lock file from config directory and restart.