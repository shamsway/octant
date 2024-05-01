# Octant Usage Configs

## Running Ansible in check mode

ansible-playbook homelab.yml -i inventory/groups.yml --check --tags "$(ROLE)"

ansible-playbook homelab.yml -i inventory/groups.yml -l $(HOST) --check -vvv --tags "$(ROLE)"
ansible-playbook homelab.yml -i inventory/groups.yml -l jerry.shamsway.net --check -vvv --tags nomad-root

## Aliases

Add to .bashrc:

```bash
if [ -f /mnt/services/octant/bash_aliases ]; then
    source /mnt/services/octant/bash_aliases
fi
```