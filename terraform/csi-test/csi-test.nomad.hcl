job "csi-test" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  constraint {
    attribute = "$${meta.rootless}"
    value     = "false"
  }

  group "test" {
    volume "testdata" {
      type            = "csi"
      source          = "csi-test-vol"
      attachment_mode = "file-system"
      access_mode     = "single-node-writer"
    }

    network {
      port "health" {
        to = 8080
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "csi-test"
      port     = "health"
      provider = "consul"

      check {
        type     = "http"
        path     = "/health"
        name     = "csi-test-health"
        interval = "15s"
        timeout  = "5s"
      }
    }

    restart {
      attempts = 3
      interval = "5m"
      delay    = "15s"
      mode     = "delay"
    }

    reschedule {
      delay          = "30s"
      delay_function = "exponential"
      max_delay      = "5m"
      unlimited      = true
    }

    task "sqlite-stress" {
      driver = "docker"

      volume_mount {
        volume      = "testdata"
        destination = "/data"
        read_only   = false
      }

      config {
        image   = "alpine:3.20"
        command = "/bin/sh"
        args    = ["/local/test.sh"]
        ports   = ["health"]
      }

      template {
        data = <<-SCRIPT
        #!/bin/sh

        # Install SQLite
        apk add --no-cache sqlite >/dev/null 2>&1

        DB=/data/test.db
        STATUSFILE=/tmp/status
        echo "0 0 0" > $STATUSFILE

        # Initialize DB
        sqlite3 "$DB" "CREATE TABLE IF NOT EXISTS test_data (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ts TEXT NOT NULL,
          payload TEXT NOT NULL,
          checksum TEXT NOT NULL
        );"

        # Count existing rows (persistence check)
        STARTUP_ROWS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM test_data;")
        echo "=== CSI TEST: Found $STARTUP_ROWS existing rows at startup ==="

        # Start health server in background using nc
        # Uses a status file since subshell cannot read parent vars
        while true; do
          STATS=$(cat $STATUSFILE 2>/dev/null || echo "0 0 0")
          W=$(echo "$STATS" | cut -d' ' -f1)
          F=$(echo "$STATS" | cut -d' ' -f2)
          T=$(echo "$STATS" | cut -d' ' -f3)
          BODY="{\"status\":\"ok\",\"writes\":$W,\"failures\":$F,\"total_rows\":$T,\"startup_rows\":$STARTUP_ROWS}"
          printf "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n%s" "$BODY" | nc -l -p 8080 2>/dev/null || true
        done &

        echo "=== CSI TEST: Starting write/read/verify loop ==="

        WRITE_COUNT=0
        FAIL_COUNT=0

        # Main write loop
        while true; do
          TS=$(date -u +%Y-%m-%dT%H:%M:%S)
          PAYLOAD=$(head -c 64 /dev/urandom | base64 | tr -d '\n')
          CHECKSUM=$(echo -n "$PAYLOAD" | sha256sum | cut -d' ' -f1)

          if sqlite3 "$DB" "PRAGMA journal_mode=WAL; INSERT INTO test_data (ts, payload, checksum) VALUES ('$TS', '$PAYLOAD', '$CHECKSUM');"; then
            VERIFY=$(sqlite3 "$DB" "SELECT checksum FROM test_data WHERE ts='$TS' ORDER BY id DESC LIMIT 1;")
            if [ "$VERIFY" = "$CHECKSUM" ]; then
              WRITE_COUNT=$((WRITE_COUNT + 1))
            else
              FAIL_COUNT=$((FAIL_COUNT + 1))
              echo "VERIFY FAIL at $TS: expected=$CHECKSUM got=$VERIFY"
            fi
          else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            echo "WRITE FAIL at $TS"
          fi

          # Update status file for health server
          TOTAL=$(sqlite3 "$DB" "SELECT COUNT(*) FROM test_data;" 2>/dev/null || echo 0)
          echo "$WRITE_COUNT $FAIL_COUNT $TOTAL" > $STATUSFILE

          # Periodic integrity check and status log
          if [ $((WRITE_COUNT % 100)) -eq 0 ] && [ $WRITE_COUNT -gt 0 ]; then
            INTEGRITY=$(sqlite3 "$DB" "PRAGMA integrity_check;")
            echo "=== CSI TEST: writes=$WRITE_COUNT fails=$FAIL_COUNT total_rows=$TOTAL integrity=$INTEGRITY ==="
          fi

          sleep 1
        done
        SCRIPT

        destination = "local/test.sh"
        perms       = "0755"
        change_mode = "restart"
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }
  }
}
