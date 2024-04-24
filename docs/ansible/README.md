# Cheatsheet

Install a role on a server in check only mode:
`ansible-playbook homelab.yml -i inventory/groups.yml -l [hostname] --check -vvv --tags [role tag]`
