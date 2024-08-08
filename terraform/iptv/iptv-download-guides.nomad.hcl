job "iptv-download-guides" {
  region = "${region}"
  datacenters = ["${datacenter}"]
  type        = "batch"

  constraint {
    attribute = "$${meta.rootless}"
    value = "true"
  }

  periodic {
    crons = ["50 */2 * * *"]
    prohibit_overlap = true
  }

  group "download" {
    task "download" {
      driver = "raw_exec"

      config {
        command = "local/download_guides.sh"
      }

      env {
        http_proxy = "http://192.168.252.7:8888"
        https_proxy = "https://192.168.252.7:8888"
        SECRETS = "$${NOMAD_SECRETS_DIR}"
      }

      template {
        destination = "$${NOMAD_SECRETS_DIR}/zap2it.ini"
        perms = "775"
        data = <<EOF
[creds]{{ with nomadVar "nomad/jobs/iptv-download-guides" }}
Username: {{ .zap2it_username }}
Password: {{ .zap2it_password }}{{ end }}
[prefs]
country: USA
zipCode: 40514
historicalGuideDays: 1
lang: en
[lineup]
headendId: lineupId
lineupId: USA-lineupId-DEFAULT
device:
EOF
      }

      template {
        destination = "local/download_guides.sh"
        perms = "775"        
        data = <<EOH
#!/bin/bash
# Download Pluto Channel List
#wget -q https://i.mjh.nz/PlutoTV/us-tvh.m3u8 -O /mnt/services/tvheadend/config/data/m3u/us-tvh.m3u8
#wget -q https://i.mjh.nz/PlutoTV/us.m3u8 -O /mnt/services/tvheadend/config/data/m3u/us-tvh.m3u8
# Download Apollo Channel List
wget -q https://tvnow.best/api/list/alphaambush/nC-hQj@j93dZJiv8 -O /tmp/Apollo.m3u8
# Split Apollo Channel List into seperate M3Us
python3 /mnt/services/iptvtools/m3u-filter.py --m3u /tmp/Apollo.m3u8 --output-dir /mnt/services/tvheadend/config/data/m3u --output-file Apollo
# Download Pluto Guide
# wget -q https://i.mjh.nz/PlutoTV/us.xml.gz -O /tmp/us.xml.gz
# gunzip -f /tmp/us.xml.gz
# Download Apollo Guide
wget -q https://epg.starlite.best/utc.xml.gz -O /tmp/utc.xml.gz
gunzip -f /tmp/utc.xml.gz
#wget -q https://epg.starlite.best/utclite.xml -O /tmp/utclite.xml
python3 /mnt/services/iptvtools/zap2it-scrape.py -c $SECRETS/zap2it.ini -o /tmp/zap2it.xml
#echo '=== Pluto TV ==='
#python3 /mnt/services/iptvtools/xmltv-info.py /tmp/us.xml
echo '=== Apollo Full ==='
python3 /mnt/services/iptvtools/xmltv-info.py /tmp/utc.xml
#echo '=== Apollo Lite ==='
#python3 /mnt/services/iptvtools/xmltv-info.py /tmp/utclite.xml
echo '=== Locals ==='
python3 /mnt/services/iptvtools/xmltv-info.py /tmp/zap2it.xml
cp /tmp/*.xml /mnt/services/nginx/html/xmltv/
#cp /tmp/utc.xml /mnt/services/tvheadend/config/data/
#cp /tmp/utclite.xml /mnt/services/tvheadend/config/data/
#cp /tmp/zap2it.xml /mnt/services/tvheadend/config/data/
python3 /mnt/services/iptvtools/xmltv-merge.py /tmp/utc.xml /tmp/zap2it.xml /mnt/services/tvheadend/config/data/guide.xml
#python3 /mnt/services/iptvtools/xmltv-merge.py /tmp/temp.xml /tmp/utclite.xml /tmp/guide.xml
#python3 /mnt/services/iptvtools/xmltv-merge.py /tmp/zap2it.xml /tmp/guide.xml /mnt/services/tvheadend/config/data/guide.xml
echo '=== Merged ==='
python3 /mnt/services/iptvtools/xmltv-info.py /mnt/services/tvheadend/config/data/guide.xml
EOH
      }    
    }
  }
}