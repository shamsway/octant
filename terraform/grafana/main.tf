provider "nomad" {
  address = "http://${var.nomad}:4646"
}

data "local_file" "grafana_datasources" {
  filename = "${path.module}/grafana-datasources.yml"
}

data "local_file" "dashboard_provider" {
  filename = "${path.module}/grafana-dashboard-provider.yml"
}

data "local_file" "octant_dashboard" {
  filename = "${path.module}/dashboards/octant-overview.json"
}

resource "nomad_job" "grafana" {
  jobspec = templatefile("${path.module}/grafana.nomad.hcl", {
    region             = var.region
    datacenter         = var.datacenter
    image              = var.image
    domain             = var.domain
    certresolver       = var.certresolver
    servicename        = var.servicename
    dns                = jsonencode(var.dns)
    datasources_yaml   = data.local_file.grafana_datasources.content
    dashboard_provider = data.local_file.dashboard_provider.content
    dashboard_json     = data.local_file.octant_dashboard.content
  })
}
