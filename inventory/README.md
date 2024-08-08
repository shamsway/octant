# Ansible Inventory Instructions

## Groups

- Copy `groups.yml.example` to `groups.yml` and edit the values to match your environment. All hosts should have working DNS resolution. Using a public DNS zone is the easiest way to accomplish this uness you already have an internal DNS server running.
- Configuring directories listed under "volumes" specify where persistent data for containers should be stored, as well as whether the directory should be backed up by restic. This approach will be simplified in a later release.

## Group Variables

- Copy `all.yml.example` to `all.yml` and edit the values to match your environment.