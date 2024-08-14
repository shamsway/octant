# LibreNMS

**Description:** LibreNMS is a fully featured network monitoring system that provides a wealth of features and device support.

**Use cases:**
- Monitor network devices and servers
- Generate bandwidth and utilization graphs
- Set up alerts for network issues

**Rootless container:** No

**URL:** https://www.librenms.org/

## Usage
- Review the variables configured in both `librenms.nomad.hcl` and `mariadb.nomad.hcl`
- Deploy the MariaDB Nomad job

`nomad job run mariadb.nomad.hcl`

- Deploy LibreNMS

`nomad job run librenms.nomad.hcl`

## Volumes

* `/data`: Contains configuration, plugins, rrd database, logs, additional Monitoring plugins, additional syslog-ng config files

## Ports

* `8000`: HTTP port
* `514 514/udp`: Syslog ports (only used if you enable and run a [sidecar syslog-ng container](#syslog-ng-container))
* `162 162/udp`: Snmptrapd ports (only used if you enable and run a [sidecar snmptrapd container](#snmptrapd-container))

## Environment variables

### General

* `TZ`: The timezone assigned to the container (default `UTC`)
* `PUID`: LibreNMS user id (default `1000`)
* `PGID`: LibreNMS group id (default `1000`)
* `MEMORY_LIMIT`: PHP memory limit (default `256M`)
* `MAX_INPUT_VARS`: PHP max input vars (default `1000`)
* `UPLOAD_MAX_SIZE`: Upload max size (default `16M`)
* `CLEAR_ENV`: Clear environment in FPM workers (default `yes`)
* `FPM_PM_MAX_CHILDREN`: FPM max Children (default: `15`)
* `FPM_PM_START_SERVERS`: FPM start servers (default: `2`)
* `FPM_PM_MIN_SPARE_SERVERS`: FPM min spare servers (default: `1`)
* `FPM_PM_MAX_SPARE_SERVERS`: FPM max spare servers (default: `6`)
* `OPCACHE_MEM_SIZE`: PHP OpCache memory consumption (default `128`)
* `LISTEN_IPV6`: Enable IPv6 for Nginx (default `true`)
* `REAL_IP_FROM`: Trusted addresses that are known to send correct replacement addresses (default `0.0.0.0/32`)
* `REAL_IP_HEADER`: Request header field whose value will be used to replace the client address (default `X-Forwarded-For`)
* `LOG_IP_VAR`: Use another variable to retrieve the remote IP address for access [log_format](http://nginx.org/en/docs/http/ngx_http_log_module.html#log_format) on Nginx. (default `remote_addr`)
* `SESSION_DRIVER`: [Driver to use for session storage](https://github.com/librenms/librenms/blob/master/config/session.php) (default `file`)
* `CACHE_DRIVER`: [Driver to use for cache and locks](https://github.com/librenms/librenms/blob/master/config/cache.php) (default `database`)

### Redis

* `REDIS_HOST`: Redis host for poller synchronization
* `REDIS_SENTINEL`: Redis Sentinel host for high availability Redis cluster
* `REDIS_SENTINEL_SERVICE`: Redis Sentinel service name (default `librenms`)
* `REDIS_SCHEME`: Redis scheme (default `tcp`)
* `REDIS_PORT`: Redis port (default `6379`)
* `REDIS_PASSWORD`: Redis password
* `REDIS_DB`: Redis database (default `0`)
* `REDIS_CACHE_DB`: Redis cache database (default `1`)

### Database

* `DB_HOST`: MySQL database hostname / IP address
* `DB_PORT`: MySQL database port (default `3306`)
* `DB_NAME`: MySQL database name (default `librenms`)
* `DB_USER`: MySQL user (default `librenms`)
* `DB_PASSWORD`: MySQL password (default `librenms`)
* `DB_TIMEOUT`: Time in seconds after which we stop trying to reach the MySQL server (useful for clusters, default `60`)

### Misc

* `LIBRENMS_BASE_URL`: URL of your LibreNMS instance (default `/`)
* `LIBRENMS_SNMP_COMMUNITY`: This container's SNMP v2c community string (default `librenmsdocker`)
* `LIBRENMS_WEATHERMAP`: Enable LibreNMS [Weathermap plugin](https://docs.librenms.org/Extensions/Weathermap/) (default `false`)
* `LIBRENMS_WEATHERMAP_SCHEDULE`: CRON expression format (default `*/5 * * * *`)
* `MEMCACHED_HOST`: Hostname / IP address of a Memcached server
* `MEMCACHED_PORT`: Port of the Memcached server (default `11211`)
* `RRDCACHED_SERVER`: RRDcached server (eg. `rrdcached:42217`