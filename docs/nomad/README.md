# Nomad Operations

## Update shares available to Nomad
- Edit inventory/groups.yml
- Add the new volume(s) to volumes: group
- Run configure-mounts.yml playbook
  - All hosts: 'ansible-playbook configure-mounts.yml -i inventory/groups.yml'
  - Single host: 'ansible-playbook configure-mounts.yml -i inventory/groups.yml -l [hostname]'
- Run update-nomad.yml playbook, one host at a time. This playbook drains the host, updates the Nomad configuration, and restarts the Nomad agent.
  - Single host: 'ansible-playbook update-nomad.yml -i inventory/groups.yml -l [hostname]'