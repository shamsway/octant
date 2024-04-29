# terraform plan -var="cloudflare_token=${CLOUDFLARE_TOKEN}"
# terraform apply -var="cloudflare_token=${CLOUDFLARE_TOKEN}"
# terraform destroy -var="cloudflare_token=${CLOUDFLARE_TOKEN}"

terraform {
  required_providers {
    google = { }
    tailscale = {
      source = "tailscale/tailscale"
      version = "0.15.0"
    }    
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    oci = {
      source = "oracle/oci"
      version = "5.39.0"
    }    
  }
}

# Configure the Oracle Cloud Infrastructure provider
provider "oci" { }

variable "cloudflare_token" {
  description = "Cloudflare authentication token"
  type        = string
}

provider "cloudflare" {
  api_token = "${var.cloudflare_token}"
}

variable "domain_name" {
  default = "shamsway.net"
}

data "cloudflare_zones" "domain" {
  filter {
    name = var.domain_name
  }
}

data "external" "availability_domain" {
  program = ["python", "check_arm_availability.py"]

  query = {
    shape         = "VM.Standard.A1.Flex"
    max_instances = 1
  }
}

resource "tailscale_tailnet_key" "pigpen_key" {
  description   = "Ephemeral key for pigpen"
  reusable      = true
  ephemeral     = false
  preauthorized = true
  tags          = ["tag:cloud"]
  lifecycle {
    prevent_destroy = true
  }  
}

resource "tailscale_tailnet_key" "mickey_key" {
  description   = "Tailscale key for mickey"
  reusable      = true
  ephemeral     = false
  preauthorized = true
  tags          = ["tag:cloud"]
  lifecycle {
    prevent_destroy = true
  }  
}

resource "tailscale_tailnet_key" "tom_key" {
  description   = "Tailscale key for tom"
  reusable      = true
  ephemeral     = false
  preauthorized = true
  tags          = ["tag:cloud"]
  lifecycle {
    prevent_destroy = true
  }
}

# Create OCI compartment
resource "oci_identity_compartment" "octant_compartment" {
  compartment_id = var.tenancy_ocid
  description    = "Octant Compute OCP"
  name           = "octant"

  lifecycle {
    prevent_destroy = true
  }  
}

data "oci_objectstorage_namespace" "namespace" {
  compartment_id = oci_identity_compartment.octant_compartment.id
}

# Define necessary data sources and resources for networking
data "oci_identity_availability_domain" "ad" {
  compartment_id = oci_identity_compartment.octant_compartment.id
  ad_number      = 3
}

data "oci_core_images" "arm_images" {
  compartment_id = oci_identity_compartment.octant_compartment.id
  display_name = "Canonical-Ubuntu-22.04-aarch64-2024.02.18-0"
  shape = "VM.Standard.A1.Flex"
}

resource "oci_core_internet_gateway" "igw" {
  compartment_id = oci_identity_compartment.octant_compartment.id
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "octant-igw"
}

resource "oci_core_route_table" "rt" {
  compartment_id = oci_identity_compartment.octant_compartment.id
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "octant-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

resource "oci_core_vcn" "vcn" {
  cidr_block     = "192.168.232.0/21"
  compartment_id = oci_identity_compartment.octant_compartment.id
  display_name   = "octant-vcn"
}

resource "oci_core_subnet" "subnet01" {
  cidr_block        = "192.168.232.0/24"
  compartment_id    = oci_identity_compartment.octant_compartment.id
  vcn_id            = oci_core_vcn.vcn.id
  display_name      = "octant-subnet01"
  route_table_id    = oci_core_route_table.rt.id
  security_list_ids = [oci_core_vcn.vcn.default_security_list_id]
}

resource "oci_core_network_security_group" "nsg" {
  compartment_id = oci_identity_compartment.octant_compartment.id
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "octant-nsg"
}

resource "oci_core_network_security_group_security_rule" "allow-any-out" {
  network_security_group_id = oci_core_network_security_group.nsg.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}

resource "oci_core_network_security_group_security_rule" "allow-ssh-in" {
  network_security_group_id = oci_core_network_security_group.nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" // TCP
  source                    = var.local_ip
  source_type               = "CIDR_BLOCK"
  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

resource "oci_objectstorage_bucket" "image_bucket" {
  compartment_id = oci_identity_compartment.octant_compartment.id
  name           = "octant-image"
  namespace      = data.oci_objectstorage_namespace.namespace.namespace

  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_objectstorage_object" "octant_image_object" {
  bucket    = oci_objectstorage_bucket.image_bucket.name
  source   = "./octantnode-disk1.vmdk"
  namespace = data.oci_objectstorage_namespace.namespace.namespace
  object    = "octantnode-disk1.vmdk"

  lifecycle {
    prevent_destroy = true
  }  
}

resource "oci_core_image" "octant_image" {
  compartment_id     = oci_identity_compartment.octant_compartment.id
  display_name       = "octant-debian"
  launch_mode        = "PARAVIRTUALIZED"

  image_source_details {
    source_type    = "objectStorageTuple"
    bucket_name    = oci_objectstorage_bucket.image_bucket.name
    namespace_name = data.oci_objectstorage_namespace.namespace.namespace
    object_name    = oci_objectstorage_object.octant_image_object.object
    source_image_type = "VMDK"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Create the Always Free AMD-based compute VMs
resource "oci_core_instance" "pigpen" {
  availability_domain = data.oci_identity_availability_domain.ad.name
  compartment_id      = oci_identity_compartment.octant_compartment.id
  shape               = "VM.Standard.E2.1.Micro"
  display_name        = "pigpen"

  source_details {
    source_id   = oci_core_image.octant_image.id
    source_type = "image"
  }

  create_vnic_details {
    subnet_id = oci_core_subnet.subnet01.id
    assign_public_ip = true
    nsg_ids          = [oci_core_network_security_group.nsg.id]
  }

  extended_metadata = {
    ssh_authorized_keys = file("${var.ssh_public_key}")
  }

  connection {
    type        = "ssh"
    user        = "debian"
    private_key = file("~/.ssh/id_rsa")
    host        = self.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo sed -i 's/127.0.0.1 localhost/127.0.0.1 localhost ${oci_core_instance.pigpen.display_name}/' /etc/hosts",
      "sudo useradd -md /home/${var.admin_user} -s /bin/bash ${var.admin_user}",
      "sudo usermod -aG sudo ${var.admin_user}",
      "sudo echo '${var.admin_user} ALL=(ALL) NOPASSWD: ALL' | tee /etc/sudoers.d/${var.admin_user}",
      "sudo chmod 440 /etc/sudoers.d/${var.admin_user}",
      "sudo mkdir /home/${var.admin_user}/.ssh",
      "sudo cp ~/.ssh/authorized_keys /home/${var.admin_user}/.ssh",
      "sudo chown -R ${var.admin_user}:${var.admin_user} /home/${var.admin_user}/.ssh",
      "sudo cp /home/${var.admin_user}/.ssh/authorized_keys /root/.ssh/",
      "sudo sed -i -e 's/#PermitRootLogin no/PermitRootLogin without-password/' -e 's/PermitRootLogin no/PermitRootLogin without-password/' /etc/ssh/sshd_config", 
      "curl -fsSL https://tailscale.com/install.sh | sh",
      "sudo tailscale up --accept-routes --accept-dns=false --authkey=${tailscale_tailnet_key.pigpen_key.key}",      
      "sudo systemctl restart sshd"
    ]
  }

  provisioner "remote-exec" {
    when = destroy
    inline = [ "sudo tailscale logout" ]
  }
}

resource "oci_core_instance" "tom" {
  availability_domain = data.oci_identity_availability_domain.ad.name
  compartment_id      = oci_identity_compartment.octant_compartment.id
  shape               = "VM.Standard.E2.1.Micro"
  display_name        = "tom"

  source_details {
    source_id   = oci_core_image.octant_image.id
    source_type = "image"
  }

  create_vnic_details {
    subnet_id = oci_core_subnet.subnet01.id
    assign_public_ip = true
    nsg_ids          = [oci_core_network_security_group.nsg.id]
  }

  extended_metadata = {
    ssh_authorized_keys = file("${var.ssh_public_key}")
  }

  connection {
    type        = "ssh"
    user        = "debian"
    private_key = file("~/.ssh/id_rsa")
    host        = self.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo sed -i 's/127.0.0.1 localhost/127.0.0.1 localhost ${oci_core_instance.tom.display_name}/' /etc/hosts",
      "sudo useradd -md /home/${var.admin_user} ${var.admin_user}",
      "sudo mkdir /home/${var.admin_user}/.ssh",
      "sudo cp ~/.ssh/authorized_keys /home/${var.admin_user}/.ssh",
      "sudo chown -R ${var.admin_user}:${var.admin_user} /home/${var.admin_user}/.ssh",
      "sudo cp /home/${var.admin_user}/.ssh/authorized_keys /root/.ssh/",
      "sudo sed -i -e 's/#PermitRootLogin no/PermitRootLogin without-password/' -e 's/PermitRootLogin no/PermitRootLogin without-password/' /etc/ssh/sshd_config", 
      "curl -fsSL https://tailscale.com/install.sh | sh",
      "sudo tailscale up --accept-routes --accept-dns=false --authkey=${tailscale_tailnet_key.tom_key.key}",      
      "sudo systemctl restart sshd"
    ]
  }

  provisioner "remote-exec" {
    when = destroy
    inline = [ "sudo tailscale logout" ]
  }
} 

# Create the Always Free Arm-based Ampere A1 VM
resource "oci_core_instance" "mickey" {
  availability_domain = data.external.availability_domain.result.availability_domain
  compartment_id      = oci_identity_compartment.octant_compartment.id
  shape               = "VM.Standard.A1.Flex"
  display_name        = "mickey"

  shape_config {
    ocpus         = 4
    memory_in_gbs = 24
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.arm_images.images[0].id
  }

  create_vnic_details {
    subnet_id = oci_core_subnet.subnet01.id
    assign_public_ip = true
    nsg_ids          = [oci_core_network_security_group.nsg.id]
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
    host        = self.public_ip
  }

  extended_metadata = {
    ssh_authorized_keys = file("${var.ssh_public_key}")
  }

  provisioner "remote-exec" {
    inline = [
      "sudo sed -i 's/127.0.0.1 localhost/127.0.0.1 localhost ${oci_core_instance.mickey.display_name}/' /etc/hosts",
      "sudo useradd -md /home/${var.admin_user} ${var.admin_user}",
      "sudo mkdir /home/${var.admin_user}/.ssh",
      "sudo cp ~/.ssh/authorized_keys /home/${var.admin_user}/.ssh",
      "sudo chown -R ${var.admin_user}:${var.admin_user} /home/${var.admin_user}/.ssh",
      "sudo cp /home/${var.admin_user}/.ssh/authorized_keys /root/.ssh/",
      "sudo sed -i -e 's/#PermitRootLogin no/PermitRootLogin without-password/' -e 's/PermitRootLogin no/PermitRootLogin without-password/' /etc/ssh/sshd_config", 
      "curl -fsSL https://tailscale.com/install.sh | sh",
      "sudo tailscale up --accept-routes --accept-dns=false --authkey=${tailscale_tailnet_key.mickey_key.key}",      
      "sudo systemctl restart sshd"
    ]
  }

  provisioner "remote-exec" {
    when = destroy
    inline = [ "sudo tailscale logout" ]
  }
}


# data "oci_core_images" "amd_images" {
#   compartment_id = oci_identity_compartment.octant_compartment.id
#   operating_system = "Oracle Linux"
#   shape = "VM.Standard.E2.1.Micro"
# }

data "tailscale_device" "pigpen" {
  depends_on = [oci_core_instance.pigpen]
  hostname = oci_core_instance.pigpen.display_name
  wait_for = "30s"
}

data "tailscale_device" "mickey" {
  depends_on = [oci_core_instance.mickey]
  hostname = oci_core_instance.mickey.display_name
  wait_for = "30s"
}

data "tailscale_device" "tom" {
  depends_on = [oci_core_instance.tom]
  hostname = oci_core_instance.tom.display_name
  wait_for = "30s"
}

resource "cloudflare_record" "pigpen" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "pigpen"
  value   = data.tailscale_device.pigpen.addresses[0]
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "mickey" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "mickey"
  value   = data.tailscale_device.mickey.addresses[0]
  type    = "A"
  proxied = false
  allow_overwrite = true
}

resource "cloudflare_record" "tom" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "mickey"
  value   = data.tailscale_device.tom.addresses[0]
  type    = "A"
  proxied = false
  allow_overwrite = true
}


output "pigpen_tailscale_ip" {
  value = data.tailscale_device.pigpen.addresses[0]
}

output "pigpen_tailscale_id" {
  value = data.tailscale_device.pigpen.id
} 

output "mickey_tailscale_ip" {
  value = data.tailscale_device.mickey.addresses[0]
}

output "mickey_tailscale_id" {
  value = data.tailscale_device.mickey.id
} 

output "tom_tailscale_ip" {
  value = data.tailscale_device.tom.addresses[0]
}

output "tom_tailscale_id" {
  value = data.tailscale_device.tom.id
} 

/* resource "null_resource" "manage_known_hosts" {
  triggers = {
    hostname = "${cloudflare_record.pigpen.name}.${var.domain_name}"
  }

  provisioner "local-exec" {
    command = "ssh-keyscan -H ${self.triggers.hostname} >> ~/.ssh/known_hosts"
    on_failure = continue
  }

  provisioner "local-exec" {
    when = destroy
    command = "ssh-keygen -R ${self.triggers.hostname}"
  }
} */