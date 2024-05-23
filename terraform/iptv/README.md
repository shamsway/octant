# Configue wget proxy settings for downloads

```bash
export http_proxy="http://192.168.252.7:8888"
export https_proxy="https://192.168.252.7:8888"
```

# Notes
- Public IP API: http://[gluetun:port]/v1/publicip/ip

# Troubleshooting

- Issue: Web interface does not start. Fix: remove .lock file from config directory and restart.
- Issue: HD Homerun returns 503
  Problem: HD Homerun is streaming to a non-existent client
  Fix: Run the commands below. The hdhomerun_config tool can be installed with `brew install hdhomerun`. See docs at https://info.hdhomerun.com/info/hdhomerun_config
  
```bash
hdhomerun_config FFFFFFFF set /tuner0/lockkey force
hdhomerun_config FFFFFFFF set /tuner0/channel none
hdhomerun_config FFFFFFFF get /tuner0/status
hdhomerun_config FFFFFFFF set /tuner1/lockkey force
hdhomerun_config FFFFFFFF set /tuner1/channel none
hdhomerun_config FFFFFFFF get /tuner1/status
```