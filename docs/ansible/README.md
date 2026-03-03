# Cheatsheet
Install a role on a server:
`ansible-playbook octant.yml -i inventory/groups.yml -l [hostname] --tags [role tag]`

Install a role on a server in check only mode:
`ansible-playbook octant.yml -i inventory/groups.yml -l [hostname] --check -vvv --tags [role tag]`
