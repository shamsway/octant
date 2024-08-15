**Description:** This folder contains an Terraform example to set up a DNS zone in Cloudflare with all the necessary A records and CNAMES for octant. Additional documentation will be provided soon.

**Usage:**

Initialize Terraform
```sh
terraform init
```

Create DNS zone and records
```sh
terraform apply -auto-approve
```