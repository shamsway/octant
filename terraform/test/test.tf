# Configure the Nomad provider
provider "nomad" {
  address = "http://192.168.252.6:4646"
}

data "template_file" "job" {
  template = "${file("./http-echo.hcl.tmpl")}"
}

# Register a job
resource "nomad_job" "http-echo" {
  jobspec = "${data.template_file.job.rendered}"
}
