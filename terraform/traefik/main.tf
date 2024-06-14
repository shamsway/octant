# Configure the Nomad provider
provider "nomad" {
  address = "http://${var.nomad}:4646"
}

# Configure the Consul provider
provider "consul" {
  address = "http://${var.consul}:8500"
}

data "local_file" "traefik_toml" {
  filename = "traefik.toml"
}

data "local_file" "dynamic_toml" {
  filename = "dynamic.toml"
}

resource "nomad_variable" "cloudflare_secrets" {
  path = "nomad/jobs/traefik"
  items = {
    cloudflare_username = var.CLOUDFLARE_USERNAME
    cloudflare_api_key = var.CLOUDFLARE_API_KEY
    traefik_toml = data.local_file.traefik_toml.content
    dynamic_toml = data.local_file.dynamic_toml.content
  }
}

data "template_file" "ingress_job_template" {
  template = "${file("./ingress-lb.nomad.hcl")}"
  vars = {
    region = var.region
    datacenter = var.datacenter
  }
}

data "template_file" "traefik_job_template" {
  template = "${file("./traefik.nomad.hcl")}"
  vars = {
    region = var.region
    datacenter = var.datacenter
    image = var.image
  }
}

# Register jobs
resource "nomad_job" "traefik" {
  depends_on = [nomad_variable.cloudflare_secrets]
  jobspec = "${data.template_file.traefik_job_template.rendered}"
}

resource "nomad_job" "ingress-lb" {
  depends_on = [nomad_job.traefik]
  jobspec = "${data.template_file.ingress_job_template.rendered}"
}