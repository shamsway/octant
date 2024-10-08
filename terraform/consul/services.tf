# Example of a statically defined service in Consul. In this example, Ollama is running on a Windows PC with a GPU.

resource "consul_node" "ollama_node" {
  name    = "ollama"
  address = "192.168.1.10"

  meta = {
    "external-node"  = "true"
    "external-probe" = "true"
  }  
}

resource "consul_service" "ollama_service" {
  name    = "ollama"
  node    = "${consul_node.ollama_node.name}"
  port    = 11434
  tags    = ["llm"]
  datacenter = "${var.datacenter}"

  check {
    check_id = "service:ollama"
    name  = "alive"
    http = "http://${consul_node.ollama_node.address}:11434"
    method = "GET"
    status = "passing"
    interval = "30s"
    timeout = "5s"
  }
}