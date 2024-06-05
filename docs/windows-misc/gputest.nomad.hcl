job "gpu-test" {
  datacenters = ["shamsway"]
  type = "batch"

  // constraint {
  //   attribute = "${meta.gpu}"
  //   value = "true"
  // }

  group "smi" {
    task "smi" {
      driver = "podman"
 
      config {
        image = "docker.io/nvidia/cuda:12.4.1-base-ubuntu22.04"
        #entrypoint = ["sleep"]
        command = "/usr/bin/sleep"
        logging = {
          driver = "journald"
          options = [
            {
              "tag" = "gpu-test"
            }
          ]
        }  
      }
 

      resources {
        device "nvidia/gpu" { }
      }
    }
  }
}