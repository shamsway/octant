job "gpu-test" {
  datacenters = ["shamsway"]
  type = "batch"

  constraint {
    attribute = "${meta.gpu}"
    value = "true"
  }

  group "smi" {
    task "smi" {
      driver = "docker"
 
      config {
        image = "docker.io/nvidia/cuda:12.4.1-base-ubuntu22.04"
        #entrypoint = ["sleep"]
        command = "/usr/bin/sleep"
      }
 
      logs {
        disabled = true
      }
    //   resources {
    //     device "nvidia/gpu" {
    //       count = 1
    //     }
    //   }
    }
  }
}