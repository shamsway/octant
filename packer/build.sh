#!/bin/sh

packer build debian-12.5-zfs-vmware.pkr.hcl --var-file="debian-bookworm.pkr.json"