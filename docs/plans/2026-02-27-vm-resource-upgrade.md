# VM Resource Upgrade Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Upgrade all 3 Octant VMs from 8 GB RAM / 2 vCPUs to 24 GB RAM / 8 vCPUs, and make VM resource allocation easily configurable for future changes.

**Architecture:** Create a new `08-resize-vms.yml` playbook that gracefully shuts down VMs, redefines their libvirt domain XML with updated resource values, and restarts them. Update inventory and role defaults to reflect the new values. Add a `resize-vms` Makefile target. The playbook operates on the hypervisor and iterates over the servers group, same pattern as `01-provision-vms.yml`.

**Tech Stack:** Ansible, libvirt (virsh), KVM/QEMU

---

### Task 1: Update inventory defaults to new resource values

**Files:**
- Modify: `inventory/groups.yml:22-25` (server vars section)
- Modify: `roles/vm_provision/defaults/main.yml:5-6`

**Step 1: Update `inventory/groups.yml` server vars**

Change the `servers.vars` section from:
```yaml
    vm_ram_gb: 8
    vm_vcpus: 2
```
to:
```yaml
    vm_ram_gb: 24
    vm_vcpus: 8
```

**Step 2: Update role defaults to match new baseline**

In `roles/vm_provision/defaults/main.yml`, change:
```yaml
vm_ram_gb: 8
vm_vcpus: 2
```
to:
```yaml
vm_ram_gb: 24
vm_vcpus: 8
```

**Step 3: Commit**

```bash
git add inventory/groups.yml roles/vm_provision/defaults/main.yml
git commit -m "feat(vm): update default VM resources to 24 GB RAM and 8 vCPUs"
```

---

### Task 2: Create the VM resize playbook

**Files:**
- Create: `playbooks/08-resize-vms.yml`

**Step 1: Create the resize playbook**

Create `playbooks/08-resize-vms.yml` with this content:

```yaml
---
# Resize Octant VMs
# Shuts down VMs, redefines their libvirt domain XML with updated
# resource values (RAM, vCPUs), and restarts them.
#
# Usage:
#   ansible-playbook playbooks/08-resize-vms.yml \
#     -i inventory/hypervisors.yml -i inventory/groups.yml
#
# Override resources at runtime:
#   ansible-playbook playbooks/08-resize-vms.yml \
#     -i inventory/hypervisors.yml -i inventory/groups.yml \
#     -e vm_ram_gb=32 -e vm_vcpus=16
#
# Resize a single VM:
#   ansible-playbook playbooks/08-resize-vms.yml \
#     -i inventory/hypervisors.yml -i inventory/groups.yml \
#     -e target_vms=octant-01

- name: Resize Octant VMs
  hosts: hypervisors
  gather_facts: true
  become: true

  vars:
    libvirt_images_path: "{{ hostvars[inventory_hostname]['libvirt_images_path'] | default('/var/lib/libvirt/images') }}"
    data_disk_pool_path: "{{ hostvars[inventory_hostname]['data_disk_pool_path'] | default(libvirt_images_path) }}"
    vm_network: "{{ hostvars[inventory_hostname]['libvirt_network'] | default('default') }}"
    server_list: "{{ (target_vms | default('')) | ternary([target_vms], groups['servers'] | default([])) }}"

  tasks:
    - name: Validate server list is not empty
      ansible.builtin.fail:
        msg: "No servers to resize. Check 'servers' group in inventory or set -e target_vms=<name>."
      when: server_list | length == 0

    - name: Display resize plan
      ansible.builtin.debug:
        msg: |
          === Octant VM Resize Plan ===
          Servers: {{ server_list | join(', ') }}
          Target RAM: {{ hostvars[server_list[0]]['vm_ram_gb'] | default(24) }} GB
          Target vCPUs: {{ hostvars[server_list[0]]['vm_vcpus'] | default(8) }}
          ==============================

    - name: Resize VMs one at a time
      ansible.builtin.include_tasks: tasks/resize-single-vm.yml
      vars:
        vm_name: "{{ vm_host }}"
        vm_ram_gb: "{{ hostvars[vm_host]['vm_ram_gb'] | default(24) }}"
        vm_vcpus: "{{ hostvars[vm_host]['vm_vcpus'] | default(8) }}"
        vm_mac: "{{ hostvars[vm_host]['vm_mac'] | default(omit) }}"
        vm_ip: "{{ hostvars[vm_host]['vm_ip'] | default(omit) }}"
        vm_create_data_disk: "{{ hostvars[vm_host]['vm_create_data_disk'] | default(true) }}"
        vm_data_disk_format: "{{ hostvars[vm_host]['vm_data_disk_format'] | default('raw') }}"
        vm_create_container_disk: "{{ hostvars[vm_host]['vm_create_container_disk'] | default(true) }}"
        vm_container_disk_format: "{{ hostvars[vm_host]['vm_container_disk_format'] | default('raw') }}"
      loop: "{{ server_list }}"
      loop_control:
        loop_var: vm_host

    - name: Display resize results
      ansible.builtin.debug:
        msg: |
          === Octant VM Resize Complete ===
          {% for host in server_list %}
          {{ host }}: {{ hostvars[host]['vm_ram_gb'] | default(24) }} GB RAM, {{ hostvars[host]['vm_vcpus'] | default(8) }} vCPUs
          {% endfor %}
          ==================================
```

**Step 2: Create the included task file for single-VM resize**

Create `playbooks/tasks/resize-single-vm.yml`:

```yaml
---
# Resize a single VM - included by 08-resize-vms.yml
# Shuts down the VM, redefines its domain XML, and restarts it.

- name: "{{ vm_name }} - Check current VM state"
  community.libvirt.virt:
    command: status
    name: "{{ vm_name }}"
  register: vm_state

- name: "{{ vm_name }} - Display current state"
  ansible.builtin.debug:
    msg: "VM {{ vm_name }} is currently {{ vm_state.status }}"

- name: "{{ vm_name }} - Gracefully shut down VM"
  community.libvirt.virt:
    name: "{{ vm_name }}"
    state: shutdown
  when: vm_state.status == 'running'

- name: "{{ vm_name }} - Wait for VM to shut down"
  community.libvirt.virt:
    command: status
    name: "{{ vm_name }}"
  register: vm_shutdown_state
  until: vm_shutdown_state.status == 'shutdown'
  retries: 30
  delay: 10
  when: vm_state.status == 'running'

- name: "{{ vm_name }} - Undefine existing VM (preserving disks)"
  ansible.builtin.command:
    cmd: virsh undefine {{ vm_name }}
  changed_when: true

- name: "{{ vm_name }} - Generate updated domain XML"
  ansible.builtin.template:
    src: "{{ playbook_dir }}/../roles/vm_provision/templates/vm-domain.xml.j2"
    dest: "{{ libvirt_images_path }}/{{ vm_name }}-domain.xml"
    mode: '0644'

- name: "{{ vm_name }} - Define VM with updated resources"
  community.libvirt.virt:
    command: define
    xml: "{{ lookup('template', playbook_dir + '/../roles/vm_provision/templates/vm-domain.xml.j2') }}"

- name: "{{ vm_name }} - Start VM"
  community.libvirt.virt:
    name: "{{ vm_name }}"
    state: running

- name: "{{ vm_name }} - Wait for VM to obtain IP address"
  ansible.builtin.shell: |
    virsh domifaddr {{ vm_name }} | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1
  register: vm_ip_result
  until: vm_ip_result.stdout | length > 0
  retries: 30
  delay: 10
  changed_when: false

- name: "{{ vm_name }} - Wait for SSH to become available"
  ansible.builtin.wait_for:
    host: "{{ vm_ip_result.stdout }}"
    port: 22
    delay: 5
    timeout: 300

- name: "{{ vm_name }} - Verify new resource allocation"
  ansible.builtin.shell: |
    virsh dominfo {{ vm_name }} | grep -E '(Max memory|CPU\(s\))'
  register: vm_resources
  changed_when: false

- name: "{{ vm_name }} - Display new resources"
  ansible.builtin.debug:
    msg: |
      VM {{ vm_name }} resized successfully:
      {{ vm_resources.stdout }}
      SSH available at: {{ vm_ip_result.stdout }}
```

**Step 3: Commit**

```bash
git add playbooks/08-resize-vms.yml playbooks/tasks/resize-single-vm.yml
git commit -m "feat(vm): add resize playbook for live VM resource changes"
```

---

### Task 3: Add Makefile targets

**Files:**
- Modify: `Makefile`

**Step 1: Add resize-vms target and single-VM variant**

Add the following after the `provision-vms` target (around line 121) in the `# --- VM Deployment ---` section:

```makefile
resize-vms:
	ansible-playbook playbooks/08-resize-vms.yml $(VM_INVENTORY)

resize-vm:
	ansible-playbook playbooks/08-resize-vms.yml $(VM_INVENTORY) -e target_vms=$(VM)
```

Also add `resize-vms resize-vm` to the `.PHONY` list on line 5.

**Step 2: Commit**

```bash
git add Makefile
git commit -m "feat(make): add resize-vms and resize-vm targets"
```

---

### Task 4: Run the resize operation

**Step 1: Run the resize playbook**

```bash
make resize-vms
```

This will iterate through octant-01, octant-02, octant-03 one at a time:
- Gracefully shut down each VM
- Redefine domain XML with 24 GB RAM and 8 vCPUs
- Start the VM
- Wait for SSH
- Verify resources
- Move to next VM

**Step 2: Verify all VMs are healthy**

```bash
make health-check
```

Expected: All 3 VMs healthy with new resources.

**Step 3: Capture updated state**

```bash
make capture-state
```

---

### Task 5: Verify and commit final state

**Step 1: SSH to a VM and verify resources**

```bash
ssh admin@192.168.122.101 "free -h && nproc"
```

Expected output should show ~24 GB RAM and 8 CPUs.

**Step 2: Final commit with any state updates**

```bash
git add -A
git commit -m "docs: capture state after VM resource upgrade to 24GB/8vCPU"
```

---

## Usage Reference

After implementation, VMs can be resized via:

```bash
# Resize all VMs (uses values from inventory/groups.yml)
make resize-vms

# Resize a single VM
make resize-vm VM=octant-01

# Override values at runtime
ansible-playbook playbooks/08-resize-vms.yml \
  -i inventory/hypervisors.yml -i inventory/groups.yml \
  -e vm_ram_gb=32 -e vm_vcpus=16

# Per-host overrides in inventory/groups.yml:
# octant-01:
#   vm_ram_gb: 32    # Override for this host only
#   vm_vcpus: 16
```

## Configuration Hierarchy

Resources are resolved in this order (first found wins):
1. CLI extra vars (`-e vm_ram_gb=32`)
2. Per-host vars in `inventory/groups.yml` (`hosts.octant-01.vm_ram_gb`)
3. Group vars in `inventory/groups.yml` (`servers.vars.vm_ram_gb`)
4. Role defaults in `roles/vm_provision/defaults/main.yml`
