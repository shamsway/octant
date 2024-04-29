#!/bin/bash

terraform destroy -var="cloudflare_token=${CLOUDFLARE_TOKEN}" -target oci_core_instance.pigpen -target oci_core_instance.tom -target oci_core_instance.mickey -target cloudflare_record.pigpen -target cloudflare_record.tom -target cloudflare_record.mickey