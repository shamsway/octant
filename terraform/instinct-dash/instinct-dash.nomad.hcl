job "${servicename}" {
  region      = "${region}"
  datacenters = ["${datacenter}"]
  type        = "service"

  # Target the hypervisor node — this is where the MI300X GPUs live and where
  # the nomad-device-amdgpu plugin exposes /dev/kfd and /dev/dri to containers.
  constraint {
    attribute = "$${meta.hypervisor}"
    value     = "true"
  }

  group "${servicename}" {
    count = 1

    network {
      port "http" {
        to = 3001
      }

      dns {
        servers = ${dns}
      }
    }

    service {
      name     = "${servicename}"
      provider = "consul"
      port     = "http"

      connect {
        native = true
      }

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=false",
        "traefik.http.routers.${servicename}.rule=Host(`${servicename}.${domain}`)",
        "traefik.http.routers.${servicename}.entrypoints=web,websecure",
        "traefik.http.routers.${servicename}.tls.certresolver=${certresolver}",
        "traefik.http.routers.${servicename}.middlewares=redirect-web-to-websecure@internal",
        "diun.enable=true",
      ]

      check {
        name     = "alive"
        type     = "http"
        path     = "/api/status"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "${servicename}" {
      driver = "docker"

      config {
        image              = "${image}"
        ports              = ["http"]
        image_pull_timeout = "15m"

        # AMD GPU Compute Interface — required for amd-smi subprocess calls.
        # /dev/kfd: GPU compute queue access (ROCm runtime entrypoint).
        # /dev/dri: DRI render nodes for all physical GPU partitions.
        # Mounted directly (not via device stanza) so the dashboard sees all 8 GPUs,
        # not just a single Nomad-allocated GPU.
        # Nomad Docker driver requires the struct form; plain strings are rejected.
        devices = [
          {
            host_path      = "/dev/kfd"
            container_path = "/dev/kfd"
          },
          {
            host_path      = "/dev/dri"
            container_path = "/dev/dri"
          },
        ]

        # Docker socket — read-only; instinct-dash uses dockerode to discover
        # running vLLM containers and correlate them with GPU VRAM usage.
        # /proc — read-only; used for PID→child process mapping for VRAM attribution.
        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock:ro",
          "/proc:/proc:ro",
        ]

        # video group: grants access to /dev/kfd and /dev/dri on most distros.
        # 110 is the docker group GID on this host (match host GID for socket access).
        group_add = ["video", "110"]

        # SYS_PTRACE: required for process introspection used in GPU VRAM attribution.
        cap_add = ["SYS_PTRACE"]

        # seccomp=unconfined: amd-smi uses syscalls blocked by the default seccomp
        # profile (e.g., perf_event_open). Required for accurate GPU metrics.
        security_opt = ["seccomp=unconfined"]

        # ipc=host: shares host IPC namespace; needed for ROCm inter-process
        # communication between amd-smi and the GPU driver.
        ipc_mode = "host"

        logging {
          type = "journald"
          config {
            tag = "${servicename}"
          }
        }
      }

      env {
        NODE_ENV        = "production"
        PORT            = "3001"
        HOST            = "0.0.0.0"
        TZ              = "America/New_York"

        # Docker socket path inside container (matches the volume mount above).
        DOCKER_SOCKET   = "/var/run/docker.sock"

        # Match vLLM container image naming conventions on this host.
        # Covers standard vLLM images and ROCm-specific variants.
        IMAGE_PATTERNS  = "vllm/*,rocm/vllm*"

        # Polling interval for GPU metrics and container discovery (ms).
        POLL_INTERVAL_MS = "${poll_interval_ms}"
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
