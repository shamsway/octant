# Octant VM-Based Deployment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fully automated 3-node Octant cluster on KVM/libvirt VMs with Ceph shared storage, deployable and destroyable repeatedly.

**Architecture:** Numbered playbooks orchestrate VM provisioning on a hypervisor, then run `octant.yml` to configure Consul/Nomad/Podman on the VMs, deploy Ceph for shared storage, and apply Terraform service modules.

**Tech Stack:** Ansible, libvirt/KVM, cloud-init, Consul, Nomad, Podman, Ceph (cephadm), Terraform, 1Password + direnv

**Source repos for reference:**
- octant-demo roles: `/home/melliott/git/octant-demo/roles/`
- eai-cluster roles: `/home/melliott/git/eai-cluster/roles/`
- octant-private patterns: `/home/melliott/git/octant-private/`

---

### Task 1: Create Feature Branch and Directory Structure

**Files:**
- Create: `playbooks/` directory
- Create: `roles/vm_storage/`, `roles/vm_provision/`, `roles/ceph/`, `roles/apply-terraform/`, `roles/secrets/`
- Modify: `.gitignore` (if exists)

**Step 1: Create the feature branch**

```bash
cd /home/melliott/git/octant
git checkout -b feature/vm-deployment
```

**Step 2: Create directory structure**

```bash
mkdir -p playbooks
mkdir -p roles/vm_storage/{tasks,defaults}
mkdir -p roles/vm_provision/{tasks,defaults,templates}
mkdir -p roles/ceph/{tasks,defaults,handlers}
mkdir -p roles/apply-terraform/{tasks,defaults}
mkdir -p roles/secrets/{tasks,defaults}
```

**Step 3: Commit**

```bash
git add .
git commit -m "chore: create directory structure for VM deployment"
```

---

### Task 2: Create Inventory Examples

**Files:**
- Create: `inventory/hypervisors.yml.example`
- Modify: `inventory/groups.yml.example`
- Modify: `inventory/group_vars/all.yml.example`

**Step 1: Create hypervisors.yml.example**

```yaml
---
# Hypervisor inventory for VM-based Octant deployment
# Copy to hypervisors.yml and adjust for your environment
all:
  children:
    hypervisors:
      hosts:
        my-hypervisor:
          ansible_host: 192.168.1.10     # Your hypervisor IP (or use localhost)
          # ansible_connection: local    # Uncomment if running on the hypervisor itself
          libvirt_images_path: /var/lib/libvirt/images
          data_disk_pool_path: /var/lib/libvirt/images
          libvirt_network: default
          base_image_name: octant-base
```

**Step 2: Update groups.yml.example**

Replace the existing host entries with VM-appropriate entries. Keep the existing volumes list. Change host names to octant-01/02/03 with VM resource variables.

Reference the existing file at `inventory/groups.yml.example` - preserve the `volumes` section exactly, update only the `hosts` section and add VM resource defaults under `vars`.

**Step 3: Update group_vars/all.yml.example**

Add these sections to the existing file (keep all existing content):

```yaml
# --- VM Provisioning ---
# HashiCorp version pins (override with specific versions as needed)
consul_version: ""   # Empty string = latest from APT
nomad_version: ""    # Empty string = latest from APT
nomad_driver_podman_version: "0.6.0"

# Ceph configuration
ceph:
  fs_name: octant-services
  pool_size: 2                    # Replicas (2 for 3-node, 3 for 5+ nodes)
  mount_path: /mnt/services      # Where CephFS is mounted on all nodes
  mon_network: ""                 # Auto-detected from first node

# Terraform
terraform_execution_order:
  - traefik
  - postgres
  - registry
  - litellm
```

**Step 4: Validate YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('inventory/hypervisors.yml.example'))"
python3 -c "import yaml; yaml.safe_load(open('inventory/groups.yml.example'))"
python3 -c "import yaml; yaml.safe_load(open('inventory/group_vars/all.yml.example'))"
```

Expected: No output (valid YAML)

**Step 5: Commit**

```bash
git add inventory/
git commit -m "feat: add VM deployment inventory examples with octant-01/02/03"
```

---

### Task 3: Port vm_storage Role

**Files:**
- Create: `roles/vm_storage/tasks/main.yml`
- Create: `roles/vm_storage/defaults/main.yml`

**Step 1: Create defaults**

Port from `/home/melliott/git/octant-demo/roles/vm_storage/defaults/main.yml` with these changes:
- `vm_create_data_disk: true` (enabled by default for Ceph)
- `vm_data_disk_format: raw` (raw for Ceph OSD performance, not qcow2)
- `data_disk_pool_name: octant-data`
- `data_disk_pool_path` derived from inventory

**Step 2: Create tasks**

Port from `/home/melliott/git/octant-demo/roles/vm_storage/tasks/main.yml` with these changes:
- Data disk block is enabled by default (vm_create_data_disk: true)
- Data disk format is `raw` for Ceph OSD use
- Add `changed_when` to shell tasks

**Step 3: Validate syntax**

```bash
ansible-playbook --syntax-check -e "vm_name=test base_image_path=/tmp/test.qcow2 libvirt_images_path=/tmp" roles/vm_storage/tasks/main.yml 2>&1 || echo "Expected - tasks file not a playbook"
python3 -c "import yaml; yaml.safe_load(open('roles/vm_storage/tasks/main.yml'))"
python3 -c "import yaml; yaml.safe_load(open('roles/vm_storage/defaults/main.yml'))"
```

**Step 4: Commit**

```bash
git add roles/vm_storage/
git commit -m "feat: add vm_storage role for OS and Ceph data disk creation"
```

---

### Task 4: Port vm_provision Role

**Files:**
- Create: `roles/vm_provision/tasks/main.yml`
- Create: `roles/vm_provision/defaults/main.yml`
- Create: `roles/vm_provision/templates/cloud-init.yml.j2`
- Create: `roles/vm_provision/templates/vm-domain.xml.j2`

**Step 1: Create defaults**

Port from `/home/melliott/git/octant-demo/roles/vm_provision/defaults/main.yml` with adjustments:
- `ssh_user` should reference the `admin_user` variable from `all.yml` or default to `admin`
- `vm_group` defaults to `servers` (not `demo`)

**Step 2: Create cloud-init template**

Port from `/home/melliott/git/octant-demo/roles/vm_provision/templates/cloud-init.yml.j2`.
Key adaptation: use `admin_user` variable from octant's all.yml instead of hardcoded `demo` user.

**Step 3: Create VM domain XML template**

Port from `/home/melliott/git/octant-demo/roles/vm_provision/templates/vm-domain.xml.j2`.
The template already handles optional data disk via `vm_create_data_disk` conditional. Ensure data disk uses `raw` format when `vm_data_disk_format` is `raw`.

**Step 4: Create tasks**

Port from `/home/melliott/git/octant-demo/roles/vm_provision/tasks/main.yml`.
Key change: the `add_host` groups should include `servers` so `octant.yml` can target them.

**Step 5: Validate syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('roles/vm_provision/tasks/main.yml'))"
python3 -c "import yaml; yaml.safe_load(open('roles/vm_provision/defaults/main.yml'))"
```

**Step 6: Commit**

```bash
git add roles/vm_provision/
git commit -m "feat: add vm_provision role with cloud-init and libvirt domain templates"
```

---

### Task 5: Create 00-build-base-image.yml Playbook

**Files:**
- Create: `playbooks/00-build-base-image.yml`

**Step 1: Write the playbook**

Port from `/home/melliott/git/octant-demo/playbooks/00-build-base-image.yml`.

Key adaptations for multi-node octant:
- Base image name: `octant-base` (not `octant-demo-base`)
- Package list: include `ceph-common` and `cephadm` for Ceph support
- Remove octant-demo-specific service directories from cloud-init runcmd (those are handled by the `volumes` role or Ceph mount)
- Keep: HashiCorp APT repo setup, hashi user creation, terraform install, nomad-driver-podman install
- Add: `lvm2` package (useful for disk management)
- The `hashi_user`/`hashi_uid` variables should reference `user`/`uid` from all.yml

**Step 2: Validate syntax**

```bash
ansible-playbook --syntax-check playbooks/00-build-base-image.yml -i inventory/hypervisors.yml.example 2>&1 | head -5
```

**Step 3: Commit**

```bash
git add playbooks/00-build-base-image.yml
git commit -m "feat: add base image build playbook with Ceph package support"
```

---

### Task 6: Create 01-provision-vms.yml Playbook

**Files:**
- Create: `playbooks/01-provision-vms.yml`

**Step 1: Write the playbook**

This is a single-play playbook that runs on the hypervisor. It loops over the `servers` group from the inventory and provisions a VM for each host:

```yaml
---
# Provision Octant VMs
# Creates VMs from pre-built base image for each host in the servers group
#
# Usage:
#   ansible-playbook playbooks/01-provision-vms.yml -i inventory/hypervisors.yml
#
# Prerequisites:
#   - Base image built with playbooks/00-build-base-image.yml
#   - inventory/groups.yml with server definitions

- name: Provision Octant VMs
  hosts: hypervisors
  gather_facts: true
  become: true

  vars:
    libvirt_images_path: "{{ hostvars[inventory_hostname]['libvirt_images_path'] | default('/var/lib/libvirt/images') }}"
    base_image_name: "{{ hostvars[inventory_hostname]['base_image_name'] | default('octant-base') }}"
    base_image_path: "{{ libvirt_images_path }}/{{ base_image_name }}.qcow2"
    data_disk_pool_path: "{{ hostvars[inventory_hostname]['data_disk_pool_path'] | default(libvirt_images_path) }}"
    # Load server definitions from groups inventory
    server_list: "{{ groups['servers'] | default([]) }}"

  tasks:
    - name: Validate server list is not empty
      ansible.builtin.fail:
        msg: "No servers defined in inventory. Add hosts to the 'servers' group in your inventory."
      when: server_list | length == 0

    - name: Provision each server VM
      ansible.builtin.include_role:
        name: vm_storage
      vars:
        vm_name: "{{ item }}"
        vm_os_disk_size: "{{ hostvars[item]['vm_os_disk_size'] | default('50G') }}"
        vm_create_data_disk: "{{ hostvars[item]['vm_create_data_disk'] | default(true) }}"
        vm_data_disk_size: "{{ hostvars[item]['vm_data_disk_size'] | default('100G') }}"
      loop: "{{ server_list }}"

    - name: Create and start each VM
      ansible.builtin.include_role:
        name: vm_provision
      vars:
        vm_name: "{{ item }}"
        vm_ram_gb: "{{ hostvars[item]['vm_ram_gb'] | default(8) }}"
        vm_vcpus: "{{ hostvars[item]['vm_vcpus'] | default(2) }}"
        vm_create_data_disk: "{{ hostvars[item]['vm_create_data_disk'] | default(true) }}"
        vm_data_disk_size: "{{ hostvars[item]['vm_data_disk_size'] | default('100G') }}"
        vm_group: servers
      loop: "{{ server_list }}"

    - name: Write provisioned VMs inventory file
      ansible.builtin.template:
        src: provisioned-inventory.yml.j2
        dest: "{{ playbook_dir }}/../inventory/provisioned_vms.yml"
        mode: '0644'
      # Template needs to be created - generates inventory with IPs
```

Note: The loop-over-roles approach is adapted from the eai-cluster pattern. The octant-demo `01-provision-vm.yml` only provisions a single VM. This playbook provisions N VMs from the servers group.

A simpler alternative: create a provisioned inventory template (or use `add_host` from the vm_provision role to dynamically add hosts during the play). The vm_provision role already calls `add_host`. The generated inventory file is a convenience for subsequent standalone playbook runs.

**Step 2: Create provisioned inventory template**

Create `playbooks/templates/provisioned-inventory.yml.j2` to write a static inventory file after provisioning, so subsequent playbooks can target the VMs without re-running provisioning.

**Step 3: Validate syntax**

```bash
ansible-playbook --syntax-check playbooks/01-provision-vms.yml -i inventory/hypervisors.yml.example
```

**Step 4: Commit**

```bash
git add playbooks/01-provision-vms.yml playbooks/templates/
git commit -m "feat: add VM provisioning playbook for multi-node cluster"
```

---

### Task 7: Update octant.yml for VM Compatibility

**Files:**
- Modify: `octant.yml`

**Step 1: Review current octant.yml**

Current issues for VM deployment:
- `user: matt` is hardcoded (should use `admin_user` variable)
- References `.secrets.yml` which we're replacing with 1Password+direnv
- Missing `volumes` role (directories are created in consul-server role instead)
- Service verification task runs before roles that install the services

**Step 2: Update octant.yml**

Changes needed:
- Replace `user: matt` with `user: "{{ admin_user }}"`
- Add `ansible_ssh_common_args` for VM SSH compatibility
- Move service verification to a post-roles task
- Keep the roles list as-is (requirements, tailscale, docker, consul-*, nomad-*)
- Replace `.secrets.yml` reference with conditional include
- Add `volumes` role after `requirements` (or handle in requirements)

**Step 3: Validate syntax**

```bash
ansible-playbook --syntax-check octant.yml -i inventory/groups.yml.example
```

**Step 4: Commit**

```bash
git add octant.yml
git commit -m "feat: update octant.yml for VM deployment compatibility"
```

---

### Task 8: Update requirements Role

**Files:**
- Modify: `roles/requirements/tasks/main.yml`

**Step 1: Review current requirements role**

Located at `roles/requirements/tasks/main.yml` (466 lines). Issues identified:
- Hardcoded IP addresses in dnsmasq client config (192.168.252.*)
- `console_user` and `console_password` vars from `.secrets.yml` - will fail without them
- LibreNMS agent install may not be needed for VM deployment
- Missing `changed_when` on several command/shell tasks
- Package list includes some bare-metal-specific packages (cockpit, snmp)

**Step 2: Make targeted updates**

- Make console user creation conditional (`when: console_user is defined`)
- Make LibreNMS agent install conditional (`when: install_librenms_agent | default(false)`)
- Make cockpit/snmp install conditional or move to a separate optional block
- Variablize the dnsmasq DNS server IPs instead of hardcoding 192.168.252.*
- Add `changed_when: false` to the `usermod -L` command
- Add HashiCorp APT repo setup (currently handled in packer/cloud-init but not in the role itself)
- Add version-pinned package installation support: `consul={{ consul_version }}` when `consul_version` is not empty

**Step 3: Validate syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('roles/requirements/tasks/main.yml'))"
```

**Step 4: Commit**

```bash
git add roles/requirements/
git commit -m "feat: update requirements role for VM deployment compatibility"
```

---

### Task 9: Update install-hashi Role for Version Pinning

**Files:**
- Modify: `roles/install-hashi/tasks/main.yml`

**Step 1: Review current role**

The role at `roles/install-hashi/tasks/main.yml` uses `state: latest` with `only_upgrade: true`. This means it installs the latest available version and only upgrades existing packages.

**Step 2: Update package installation task**

Change the install task to support pinned versions:

```yaml
- name: Install {{ name }}
  ansible.builtin.package:
    name: "{{ package }}{% if package_version | default('') != '' %}={{ package_version }}{% endif %}"
    state: "{% if package_version | default('') != '' %}present{% else %}latest{% endif %}"
    update_cache: yes
```

This allows passing `package_version` to pin a specific version, or omitting it for latest.

**Step 3: Validate syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('roles/install-hashi/tasks/main.yml'))"
```

**Step 4: Commit**

```bash
git add roles/install-hashi/
git commit -m "feat: add version pinning support to install-hashi role"
```

---

### Task 10: Create Ceph Role

**Files:**
- Create: `roles/ceph/tasks/main.yml`
- Create: `roles/ceph/tasks/bootstrap.yml`
- Create: `roles/ceph/tasks/add_hosts.yml`
- Create: `roles/ceph/tasks/create_osds.yml`
- Create: `roles/ceph/tasks/create_fs.yml`
- Create: `roles/ceph/tasks/mount.yml`
- Create: `roles/ceph/defaults/main.yml`
- Create: `roles/ceph/handlers/main.yml`

This is the most complex new role. Reference: `/home/melliott/git/octant-private/docs/ceph/README.md` for the manual procedure being automated.

**Step 1: Create defaults**

```yaml
---
# Ceph role defaults
ceph_fs_name: "{{ ceph.fs_name | default('octant-services') }}"
ceph_pool_size: "{{ ceph.pool_size | default(2) }}"
ceph_mount_path: "{{ ceph.mount_path | default('/mnt/services') }}"
ceph_first_mon: "{{ groups['servers'][0] }}"
ceph_skip_monitoring: true
```

**Step 2: Create main.yml dispatcher**

```yaml
---
# Ceph deployment - runs stages in order
# Stage 1: Bootstrap on first monitor node
# Stage 2: Add remaining hosts
# Stage 3: Create OSDs from data disks
# Stage 4: Create CephFS filesystem
# Stage 5: Mount CephFS on all nodes

- name: Bootstrap Ceph cluster
  ansible.builtin.include_tasks: bootstrap.yml
  when: inventory_hostname == ceph_first_mon

- name: Add hosts to Ceph cluster
  ansible.builtin.include_tasks: add_hosts.yml
  when: inventory_hostname == ceph_first_mon

- name: Create OSDs from data disks
  ansible.builtin.include_tasks: create_osds.yml
  when: inventory_hostname == ceph_first_mon

- name: Create CephFS filesystem
  ansible.builtin.include_tasks: create_fs.yml
  when: inventory_hostname == ceph_first_mon

- name: Mount CephFS on all nodes
  ansible.builtin.include_tasks: mount.yml
```

**Step 3: Create bootstrap.yml**

Key commands:
- `apt-get install -y cephadm ceph-common`
- `cephadm bootstrap --mon-ip {{ ansible_default_ipv4.address }} --skip-monitoring-stack --single-host-defaults --allow-fqdn-hostname`
- Copy ceph SSH public key for cluster expansion
- Wait for ceph health to be HEALTH_OK or HEALTH_WARN

**Step 4: Create add_hosts.yml**

Key commands:
- Copy ceph SSH key to each additional node
- `ceph orch host add {{ item }} {{ hostvars[item].ansible_host }}`
- `ceph orch apply mon --placement="{{ groups['servers'] | join(',') }}"`
- Wait for all monitors to join

**Step 5: Create create_osds.yml**

Key commands:
- `ceph orch apply osd --all-available-devices`
- Wait for OSDs to come online
- Verify replication is working

**Step 6: Create create_fs.yml**

Key commands:
- `ceph fs volume create {{ ceph_fs_name }}`
- Adjust pool sizes: `ceph osd pool set cephfs.{{ ceph_fs_name }}.data size {{ ceph_pool_size }}`
- Same for metadata pool
- Wait for filesystem to be active

**Step 7: Create mount.yml**

Key commands:
- Get ceph auth key: `ceph auth get-key client.admin`
- Write key to `/etc/ceph/ceph.client.admin.keyring` on each node
- Create mount point
- Add fstab entry for CephFS mount
- Mount the filesystem
- Verify by writing a test file from one node and reading from another

**Step 8: Create handlers**

```yaml
---
- name: Restart ceph
  ansible.builtin.shell: cephadm shell -- ceph orch restart
  changed_when: true
```

**Step 9: Validate syntax**

```bash
for f in roles/ceph/tasks/*.yml roles/ceph/defaults/main.yml roles/ceph/handlers/main.yml; do
  python3 -c "import yaml; yaml.safe_load(open('$f'))" && echo "$f OK" || echo "$f FAILED"
done
```

**Step 10: Commit**

```bash
git add roles/ceph/
git commit -m "feat: add ceph role for automated cephadm deployment"
```

---

### Task 11: Create 02-deploy-ceph.yml Playbook

**Files:**
- Create: `playbooks/02-deploy-ceph.yml`

**Step 1: Write the playbook**

```yaml
---
# Deploy Ceph Distributed Storage
# Bootstraps cephadm cluster, adds OSDs, creates CephFS, mounts on all nodes
#
# Usage:
#   ansible-playbook playbooks/02-deploy-ceph.yml -i inventory/provisioned_vms.yml
#
# Prerequisites:
#   - VMs provisioned with playbooks/01-provision-vms.yml
#   - octant.yml has been run (base packages installed)
#   - Each VM has a secondary disk at /dev/vdb

- name: Deploy Ceph Storage Cluster
  hosts: servers
  gather_facts: true
  become: true

  roles:
    - role: ceph
```

**Step 2: Validate syntax**

```bash
ansible-playbook --syntax-check playbooks/02-deploy-ceph.yml -i inventory/groups.yml.example
```

**Step 3: Commit**

```bash
git add playbooks/02-deploy-ceph.yml
git commit -m "feat: add Ceph deployment playbook"
```

---

### Task 12: Port apply-terraform Role

**Files:**
- Create: `roles/apply-terraform/tasks/main.yml`
- Create: `roles/apply-terraform/tasks/apply_module.yml`
- Create: `roles/apply-terraform/defaults/main.yml`

**Step 1: Port from octant-demo**

Copy the role from `/home/melliott/git/octant-demo/roles/apply-terraform/` with these adjustments:
- `terraform_base_path` should point to the octant terraform directory (deployed to the VM or referenced locally)
- Remove the `restart_systemd_resolved` task at the top (not needed in multi-node context)
- Ensure the role runs as the `hashi` user for Terraform operations

**Step 2: Validate syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('roles/apply-terraform/tasks/main.yml'))"
python3 -c "import yaml; yaml.safe_load(open('roles/apply-terraform/tasks/apply_module.yml'))"
python3 -c "import yaml; yaml.safe_load(open('roles/apply-terraform/defaults/main.yml'))"
```

**Step 3: Commit**

```bash
git add roles/apply-terraform/
git commit -m "feat: add apply-terraform role for modular service deployment"
```

---

### Task 13: Create 03-deploy-services.yml Playbook

**Files:**
- Create: `playbooks/03-deploy-services.yml`

**Step 1: Write the playbook**

This playbook runs on a single server node (the first one) to apply Terraform modules. Terraform talks to Consul/Nomad APIs which distribute jobs across the cluster.

```yaml
---
# Deploy Octant Services via Terraform
#
# Usage:
#   ansible-playbook playbooks/03-deploy-services.yml -i inventory/provisioned_vms.yml
#
# Deploys: Traefik, Postgres, Registry, LiteLLM (configurable)

- name: Deploy Octant Services
  hosts: servers[0]
  gather_facts: true
  become: true

  pre_tasks:
    - name: Verify Consul is accessible
      ansible.builtin.uri:
        url: "http://localhost:8500/v1/status/leader"
        return_content: true
      register: consul_leader
      retries: 5
      delay: 10
      until: consul_leader.status == 200

    - name: Verify Nomad is accessible
      ansible.builtin.uri:
        url: "http://localhost:4646/v1/status/leader"
        return_content: true
      register: nomad_leader
      retries: 5
      delay: 10
      until: nomad_leader.status == 200

  roles:
    - role: apply-terraform
```

**Step 2: Validate and commit**

```bash
ansible-playbook --syntax-check playbooks/03-deploy-services.yml -i inventory/groups.yml.example
git add playbooks/03-deploy-services.yml
git commit -m "feat: add service deployment playbook with Consul/Nomad pre-checks"
```

---

### Task 14: Create 04-health-check.yml Playbook

**Files:**
- Create: `playbooks/04-health-check.yml`

**Step 1: Write the playbook**

Health checks to validate the full stack:

```yaml
---
# Octant Cluster Health Check
#
# Usage:
#   ansible-playbook playbooks/04-health-check.yml -i inventory/provisioned_vms.yml

- name: Octant Cluster Health Check
  hosts: servers
  gather_facts: true
  become: true

  tasks:
    # Per-node checks
    - name: Check Consul server is running
      ansible.builtin.systemd:
        name: consul-server
      register: consul_svc
      failed_when: consul_svc.status.ActiveState != "active"

    - name: Check Nomad server is running
      ansible.builtin.systemd:
        name: nomad-server
      register: nomad_svc
      failed_when: nomad_svc.status.ActiveState != "active"

    - name: Check CephFS is mounted
      ansible.builtin.shell: mountpoint -q /mnt/services
      changed_when: false

    - name: Check Consul members
      ansible.builtin.shell: consul members
      register: consul_members
      changed_when: false
      when: inventory_hostname == groups['servers'][0]

    - name: Display Consul members
      ansible.builtin.debug:
        var: consul_members.stdout_lines
      when: inventory_hostname == groups['servers'][0]

    - name: Check Nomad node status
      ansible.builtin.shell: nomad node status
      register: nomad_nodes
      changed_when: false
      when: inventory_hostname == groups['servers'][0]

    - name: Display Nomad nodes
      ansible.builtin.debug:
        var: nomad_nodes.stdout_lines
      when: inventory_hostname == groups['servers'][0]

    - name: Check Ceph cluster health
      ansible.builtin.shell: ceph status
      register: ceph_status
      changed_when: false
      when: inventory_hostname == groups['servers'][0]

    - name: Display Ceph status
      ansible.builtin.debug:
        var: ceph_status.stdout_lines
      when: inventory_hostname == groups['servers'][0]

    - name: Display health check summary
      ansible.builtin.debug:
        msg: |
          ================================================================================
          OCTANT CLUSTER HEALTH CHECK - {{ inventory_hostname }}
          ================================================================================
          Consul: {{ consul_svc.status.ActiveState }}
          Nomad:  {{ nomad_svc.status.ActiveState }}
          CephFS: mounted at /mnt/services
          ================================================================================
```

**Step 2: Validate and commit**

```bash
ansible-playbook --syntax-check playbooks/04-health-check.yml -i inventory/groups.yml.example
git add playbooks/04-health-check.yml
git commit -m "feat: add cluster health check playbook"
```

---

### Task 15: Create 99-teardown.yml Playbook

**Files:**
- Create: `playbooks/99-teardown.yml`

**Step 1: Write the playbook**

Two plays: first on VMs (cleanup services), then on hypervisor (destroy VMs).

```yaml
---
# Teardown Octant Cluster
# Destroys all VMs and cleans up resources for fresh rebuild
#
# Usage:
#   ansible-playbook playbooks/99-teardown.yml -i inventory/hypervisors.yml
#
# WARNING: This destroys all VMs and data. Use with caution.

- name: Confirm teardown
  hosts: localhost
  gather_facts: false
  tasks:
    - name: Confirm cluster destruction
      ansible.builtin.pause:
        prompt: |
          WARNING: This will destroy all Octant VMs and their data.
          Press Enter to continue, or Ctrl+C to abort.

- name: Destroy Octant VMs
  hosts: hypervisors
  gather_facts: true
  become: true

  vars:
    libvirt_images_path: "{{ hostvars[inventory_hostname]['libvirt_images_path'] | default('/var/lib/libvirt/images') }}"
    data_disk_pool_path: "{{ hostvars[inventory_hostname]['data_disk_pool_path'] | default(libvirt_images_path) }}"
    server_list: "{{ groups['servers'] | default([]) }}"
    preserve_base_image: true

  tasks:
    - name: Destroy each VM
      block:
        - name: Destroy VM {{ item }}
          ansible.builtin.shell: virsh destroy {{ item }}
          ignore_errors: true
          changed_when: true

        - name: Undefine VM {{ item }}
          ansible.builtin.shell: virsh undefine {{ item }}
          ignore_errors: true
          changed_when: true

        - name: Remove VM disks for {{ item }}
          ansible.builtin.file:
            path: "{{ disk }}"
            state: absent
          loop:
            - "{{ libvirt_images_path }}/{{ item }}.qcow2"
            - "{{ data_disk_pool_path }}/{{ item }}-data.img"
            - "{{ libvirt_images_path }}/{{ item }}-cloud-init.iso"
            - "{{ libvirt_images_path }}/cloud-init/{{ item }}-user-data"
            - "{{ libvirt_images_path }}/cloud-init/{{ item }}-meta-data"
          loop_control:
            loop_var: disk
      loop: "{{ server_list }}"

    - name: Remove provisioned VMs inventory
      ansible.builtin.file:
        path: "{{ playbook_dir }}/../inventory/provisioned_vms.yml"
        state: absent

    - name: Display teardown complete
      ansible.builtin.debug:
        msg: |
          ================================================================================
          OCTANT CLUSTER TEARDOWN COMPLETE
          ================================================================================
          Destroyed VMs: {{ server_list | join(', ') }}
          Base image: {{ 'PRESERVED' if preserve_base_image else 'REMOVED' }}
          To rebuild: ansible-playbook playbooks/site.yml -i inventory/hypervisors.yml
          ================================================================================
```

**Step 2: Validate and commit**

```bash
ansible-playbook --syntax-check playbooks/99-teardown.yml -i inventory/hypervisors.yml.example
git add playbooks/99-teardown.yml
git commit -m "feat: add teardown playbook for clean cluster destruction"
```

---

### Task 16: Create site.yml Orchestrator

**Files:**
- Create: `playbooks/site.yml`

**Step 1: Write site.yml**

This is the top-level orchestrator that runs the full deployment sequence:

```yaml
---
# Octant Full Deployment Orchestrator
# Runs all deployment phases in sequence
#
# Usage:
#   ansible-playbook playbooks/site.yml -i inventory/hypervisors.yml
#
# Phases:
#   00 - Build base image (skipped if exists)
#   01 - Provision VMs
#   octant.yml - Configure Consul/Nomad/Podman
#   02 - Deploy Ceph
#   03 - Deploy services
#   04 - Health check

- name: "Phase 0: Build Base Image"
  ansible.builtin.import_playbook: 00-build-base-image.yml

- name: "Phase 1: Provision VMs"
  ansible.builtin.import_playbook: 01-provision-vms.yml

- name: "Phase 2: Configure Cluster"
  ansible.builtin.import_playbook: ../octant.yml

- name: "Phase 3: Deploy Ceph"
  ansible.builtin.import_playbook: 02-deploy-ceph.yml

- name: "Phase 4: Deploy Services"
  ansible.builtin.import_playbook: 03-deploy-services.yml

- name: "Phase 5: Health Check"
  ansible.builtin.import_playbook: 04-health-check.yml
```

Note: `import_playbook` requires the imported playbooks to work with the inventory passed at the command line. The VM provisioning playbook uses `add_host` to make provisioned VMs available to subsequent plays. For `octant.yml`, the VMs need to be in the `servers` group, which the vm_provision role handles via `add_host`.

**Step 2: Validate and commit**

```bash
ansible-playbook --syntax-check playbooks/site.yml -i inventory/hypervisors.yml.example
git add playbooks/site.yml
git commit -m "feat: add site.yml orchestrator for full deployment sequence"
```

---

### Task 17: Create secrets Role

**Files:**
- Create: `roles/secrets/tasks/main.yml`
- Create: `roles/secrets/defaults/main.yml`

**Step 1: Create defaults**

```yaml
---
# Secrets role defaults
secrets_provider: "1password"  # Options: 1password, env_file, none
op_vault_name: "Octant"
secrets_env_file: "{{ datadir }}/.env"
```

**Step 2: Create tasks**

The role should:
- Check if 1Password CLI (`op`) is available
- If available, use `op inject` to render `.env.template` → `.env`
- If not available, check for an existing `.env` file
- Deploy the `.env` file to the VM with secure permissions
- Make variables available to Terraform via the apply-terraform role

Reference the octant-demo secrets role at `/home/melliott/git/octant-demo/roles/secrets/` and the octant-private pattern at `/home/melliott/git/octant-private/docs/secrets/`.

**Step 3: Validate and commit**

```bash
python3 -c "import yaml; yaml.safe_load(open('roles/secrets/tasks/main.yml'))"
git add roles/secrets/
git commit -m "feat: add secrets role with 1Password integration"
```

---

### Task 18: Update Makefile

**Files:**
- Modify: `Makefile`

**Step 1: Add VM lifecycle targets**

Add these targets to the existing Makefile (keep all existing targets):

```makefile
# --- VM Deployment ---
VM_INVENTORY := inventory/hypervisors.yml

build-base-image:
	ansible-playbook playbooks/00-build-base-image.yml -i $(VM_INVENTORY)

provision-vms:
	ansible-playbook playbooks/01-provision-vms.yml -i $(VM_INVENTORY)

deploy-cluster:
	ansible-playbook octant.yml -i inventory/provisioned_vms.yml

deploy-ceph:
	ansible-playbook playbooks/02-deploy-ceph.yml -i inventory/provisioned_vms.yml

deploy-services:
	ansible-playbook playbooks/03-deploy-services.yml -i inventory/provisioned_vms.yml

health-check:
	ansible-playbook playbooks/04-health-check.yml -i inventory/provisioned_vms.yml

deploy-vm: build-base-image provision-vms deploy-cluster deploy-ceph deploy-services health-check

teardown:
	ansible-playbook playbooks/99-teardown.yml -i $(VM_INVENTORY)

rebuild: teardown deploy-vm
```

**Step 2: Commit**

```bash
git add Makefile
git commit -m "feat: add VM lifecycle targets to Makefile"
```

---

### Task 19: Adapt Terraform Modules for Multi-Node

**Files:**
- Review/modify: `terraform/traefik/`, `terraform/postgres/`, `terraform/litellm/`
- Create: `terraform/registry/` (if not already present from octant-demo)

**Step 1: Review existing terraform modules**

The existing octant terraform modules define Nomad jobs. Check each of the four target modules for:
- Volume references that match the `volumes` list in `groups.yml.example`
- Consul service registration
- Any hardcoded single-node assumptions

**Step 2: Adjust if needed**

Most modules should work as-is since they're Nomad job definitions that Nomad schedules across available nodes. The main check is that volume names match and Consul addresses use `localhost` (since Consul agent runs on each node).

If the octant repo doesn't have a `terraform/registry/` module, port it from octant-demo at `/home/melliott/git/octant-demo/terraform/registry/`.

**Step 3: Commit any changes**

```bash
git add terraform/
git commit -m "feat: adjust terraform modules for multi-node deployment"
```

---

### Task 20: Integration Testing - First Full Deployment

**Files:** None (testing)

**Step 1: Create actual inventory files from examples**

```bash
cp inventory/hypervisors.yml.example inventory/hypervisors.yml
cp inventory/groups.yml.example inventory/groups.yml
cp inventory/group_vars/all.yml.example inventory/group_vars/all.yml
# Edit each file for your actual environment
```

**Step 2: Build base image**

```bash
make build-base-image
```

Expected: Base image created at configured path. Verify with `qemu-img info`.

**Step 3: Provision VMs**

```bash
make provision-vms
```

Expected: 3 VMs running, SSH accessible, IPs in provisioned_vms.yml.

**Step 4: Deploy cluster**

```bash
make deploy-cluster
```

Expected: Consul and Nomad running on all 3 nodes. Verify with `consul members` and `nomad node status`.

**Step 5: Deploy Ceph**

```bash
make deploy-ceph
```

Expected: Ceph cluster healthy, CephFS mounted at `/mnt/services` on all nodes.

**Step 6: Deploy services**

```bash
make deploy-services
```

Expected: Traefik, Postgres, Registry, LiteLLM running as Nomad jobs.

**Step 7: Health check**

```bash
make health-check
```

Expected: All checks pass.

**Step 8: Teardown and rebuild**

```bash
make teardown
make deploy-vm
```

Expected: Full cycle completes without manual intervention.

---

### Task 21: Fix Issues from First Deployment

**Files:** Various (depends on what breaks)

This task is a placeholder for the inevitable debugging and fixes discovered during Task 20. Common issues to watch for:

- Cloud-init timing (SSH not ready, packages not installed)
- Consul/Nomad quorum formation timing
- Ceph OSD detection of `/dev/vdb` (may need explicit device path)
- CephFS mount permissions for the `hashi` user
- Terraform module variable mismatches
- DNS resolution between nodes
- Inventory variable precedence conflicts

For each issue:
1. Identify the root cause
2. Fix the minimal set of files
3. Run `make teardown && make deploy-vm` to verify
4. Commit the fix

---

### Task 22: Second Full Deployment (Validation)

**Files:** None (testing)

After fixing issues from Task 21, run a complete teardown and rebuild to confirm the fixes work end-to-end:

```bash
make rebuild
```

Expected: Clean deployment with no manual intervention. All health checks pass.

**Step 2: Document any remaining manual steps**

If any steps still require manual intervention, document them in `docs/deployment-notes.md`.

**Step 3: Final commit**

```bash
git add .
git commit -m "docs: add deployment notes from validation testing"
```

---

## Task Dependency Summary

```
Task 1 (branch + dirs)
  → Task 2 (inventory)
  → Task 3 (vm_storage role)
  → Task 4 (vm_provision role)
    → Task 5 (00-build-base-image.yml)
    → Task 6 (01-provision-vms.yml)
  → Task 7 (octant.yml updates)
  → Task 8 (requirements role updates)
  → Task 9 (install-hashi updates)
  → Task 10 (ceph role) → Task 11 (02-deploy-ceph.yml)
  → Task 12 (apply-terraform role) → Task 13 (03-deploy-services.yml)
  → Task 14 (04-health-check.yml)
  → Task 15 (99-teardown.yml)
  → Task 16 (site.yml)
  → Task 17 (secrets role)
  → Task 18 (Makefile)
  → Task 19 (terraform modules)
    → Task 20 (first deployment test)
      → Task 21 (fix issues)
        → Task 22 (validation rebuild)
```

Tasks 2-19 can largely be done in parallel (they're independent file creation/modification). Tasks 20-22 are sequential and depend on all prior tasks.

---

## Phase 2: Ingress & DNS (feature/app-migration)

Tasks 1-22 above are complete. The following tasks extend the deployment with HAProxy ingress and DNS configuration.

### Task 23: HAProxy Ingress on Hypervisor (DONE)

Deploy HAProxy on the hypervisor to load-balance traffic across VMs with active health checks. Proxies ports 443 (Traefik HTTPS), 4646 (Nomad API), 8500 (Consul API), 9002 (Traefik dashboard). See `docs/plans/2026-02-24-haproxy-ingress-design.md`.

- `roles/haproxy/` - role with tasks + config template
- `playbooks/02.5-deploy-haproxy.yml` / `playbooks/02.5-remove-haproxy.yml`
- Makefile: `deploy-haproxy`, `remove-haproxy`, integrated into `deploy-vm` and `teardown`

### Task 24: Templatize traefik.toml (DONE)

- Templatized `traefik.toml` with `${domain}`, `${consul}`, `${datacenter}`, `${admin_email}`, `${certresolver}`
- Changed `main.tf` from `data "local_file"` to `data "template_file"` for traefik.toml
- Added `admin_email` variable to `variables.tf` and `apply_module.yml`
- Removed file provider and `dynamic.toml` (all routing via Consul Catalog)
- Removed static routers that intercepted Consul Catalog routes
- Fixed TLS config: `[tls]` → `[providers.consulcatalog.endpoint.tls]`, field names for v3
- Disabled `connectAware`/`connectByDefault` (no Consul Connect in use)
- Changed Consul endpoint to `consul.lab.example.com:8501`

### Task 25: Create DNS terraform for lab.example.com (DONE)

- Created `terraform/dns-lab/main.tf` with wildcard `*.lab.example.com` → 192.168.1.100
- Added individual `consul.lab.example.com` A records for each VM (DNS round-robin)

### Task 26: Deploy and Test Ingress (DONE)

- HAProxy deployed with health checks on ports 443, 4646, 8500, 9002
- DNS records applied via `terraform/dns-lab/`
- Cloudflare DNS-01 ACME certificates issued for all 12 services
- HTTPS routing verified end-to-end via `https://<service>.lab.example.com`

### Task 27: Traefik Fixes & Cloudflare 1Password Integration (DONE)

Fixes applied during ingress testing:

- **Duplicate dashboard router:** Renamed `traefik-admin` router from `dashboard` to `traefik-dash` (was conflicting with `traefik-http` router of the same name)
- **Removed Consul Connect blocks:** Removed `connect { native = true }` from `traefik-admin` and `traefik-metrics` service blocks
- **Removed stale dynamic.toml:** Deleted empty `dynamic.toml` file and all references in `main.tf`
- **1Password for Cloudflare creds:** Switched from `.env` file passthrough to 1Password Terraform provider (`api_cloudflare_key` item in Octant vault, `.username` for email, `.credential` for Global API Key)
- **Removed .env passthrough:** Cleared `terraform_module_env_patterns.traefik` list, removed `CLOUDFLARE_USERNAME`/`CLOUDFLARE_API_KEY` variables from `variables.tf`
- **Static ports for Traefik:** Changed HTTP (80) and HTTPS (443) from dynamic to static port allocation in Nomad job spec (HAProxy forwards to these ports on the VMs)
- **Container storage disk:** Added third VM disk (`/dev/vdc`, 30G, XFS) for Podman container storage via `roles/container-storage/`
- **Service container fixes:** Loki (delete_request_store), Grafana (removed config mount), Qdrant/Tempo (userns uid mapping), PGAdmin (email + memory), Alloy (template parse fix)
- **CephFS ownership:** Volumes owned by `hashi:hashi` (uid 2000) — rootless Podman keep-id maps host UID
