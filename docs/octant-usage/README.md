# Octant Usage Configs

## Running Ansible in check mode

ansible-playbook homelab.yml -i inventory/groups.yml --check --tags "$(ROLE)"

ansible-playbook homelab.yml -i inventory/groups.yml -l $(HOST) --check -vvv --tags "$(ROLE)"
ansible-playbook homelab.yml -i inventory/groups.yml -l jerry.shamsway.net --check -vvv --tags nomad-root