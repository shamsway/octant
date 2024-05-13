job "iptv-download-guides" {
  region = "home"
  datacenters = ["shamsway"]
  type        = "batch"

  constraint {
    attribute = "${meta.rootless}"
    value = "true"
  }

  periodic {
    crons = ["30 */4 * * *"]
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
      }

      template {
        data = <<EOH
#!/bin/bash
wget -q https://i.mjh.nz/PlutoTV/us-tvh.m3u8 -O /mnt/services/tvheadend/config/data/m3u/us-tvh.m3u8
wget -q https://tvnow.best/api/list/alphaambush/nC-hQj@j93dZJiv8 -O /tmp/Apollo.m3u8
python3 /mnt/services/iptvtools/m3u-filter.py --m3u /tmp/Apollo.m3u8 --output-dir /mnt/services/tvheadend/config/data/m3u --output-file Apollo
wget -q https://i.mjh.nz/PlutoTV/us.xml.gz -O /tmp/us.xml.gz
gunzip -f /tmp/us.xml.gz
wget -q https://epg.tvnow.best/utc.xml.gz -O /tmp/utc.xml.gz
gunzip -f /tmp/utc.xml.gz
python3 /mnt/services/iptvtools/xmltv-info.py /tmp/us.xml
python3 /mnt/services/iptvtools/xmltv-info.py /tmp/utc.xml
python3 /mnt/services/iptvtools/xmltv-merge.py /tmp/us.xml /tmp/utc.xml /mnt/services/tvheadend/config/data/guide.xml
EOH
        destination = "local/download_guides.sh"
        perms = "775"
      }    
    }
  }
}