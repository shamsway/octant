# Graceful Shutdown & Snapshot Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create two playbooks — `08-graceful-shutdown.yml` (terraform destroy, Ceph flags, unmount CephFS, stop Nomad/Consul) and `09-snapshot-cluster.yml` (OS-only VM disk snapshots) — plus Makefile targets.

**Architecture:** Single orchestration playbook with two plays (localhost for terraform, servers for system operations). Separate snapshot playbook runs on hypervisors after VMs are shut down. Reuses existing `apply-terraform` role for terraform destroy and follows patterns from existing stop-nomad/stop-consul playbooks.

**Tech Stack:** Ansible, Terraform (via apply-terraform role), Ceph CLI (cephadm), libvirt/virsh

**Spec:** `docs/superpowers/specs/2026-03-10-graceful-shutdown-design.md`

---

## Chunk 1: Graceful Shutdown Playbook

### Task 1: Create the graceful shutdown playbook

**Files:**
- Create: `playbooks/08-graceful-shutdown.yml`

**Reference files (read before starting):**
- `playbooks/06-destroy-services.yml` — pattern for terraform destroy play (localhost, apply-terraform role)
- `playbooks/03-deploy-services.yml` — pattern for API pre-flight checks
- `stop-nomad.yml` (repo root) — pattern for stopping Nomad (serial: 1, agents then servers)
- `stop-consul.yml` (repo root) — pattern for stopping Consul (serial: 1, agents then servers)
- `roles/apply-terraform/defaults/main.yml` — `terraform_execution_order` definition
- `roles/ceph/tasks/mount.yml` — CephFS mount details (`ceph_mount_path`, fstab options)

**NOTE:** The root-level `stop-nomad.yml` and `stop-consul.yml` use `vars_files: .secrets.yml` which resolves
relative to the playbook file location. Since our new playbook lives in `playbooks/`, we do NOT use `vars_files`
here — the admin_user variable comes from inventory group_vars, not `.secrets.yml`.

- [ ] **Step 1: Create the playbook file with header and Play 1 (terraform destroy)**

Write `playbooks/08-graceful-shutdown.yml` with:

```yaml
---
# Graceful Cluster Shutdown
# Stops all services and daemons in dependency order for clean shutdown
#
# Usage:
#   make shutdown
#   make shutdown ARGS="-e confirm_shutdown=yes"    # Skip confirmation prompt
#
# This playbook:
#   1. Saves pre-shutdown state (running Nomad jobs, Consul services)
#   2. Runs terraform destroy on all services (reverse execution order)
#   3. Sets Ceph OSD maintenance flags (noout, nobackfill, norecover)
#   4. Unmounts CephFS on all nodes
#   5. Stops Nomad agents and servers
#   6. Stops Consul agents and servers
#
# After shutdown, optionally run:
#   make snapshot    # Create VM disk snapshots
#
# After restart, unset Ceph flags:
#   ssh octant-01 'sudo ceph osd unset noout && sudo ceph osd unset nobackfill && sudo ceph osd unset norecover'

- name: Graceful Shutdown - Destroy Services
  hosts: localhost
  connection: local
  gather_facts: true

  vars:
    cluster_address: "{{ hostvars[groups['servers'][0]].ansible_host | default(groups['servers'][0]) }}"
    confirm_shutdown: "no"
    shutdown_state_dir: "{{ playbook_dir }}/.shutdown-state"

  pre_tasks:
    - name: Verify Consul is accessible
      ansible.builtin.uri:
        url: "http://{{ cluster_address }}:8500/v1/status/leader"
        return_content: true
      register: consul_leader
      retries: 3
      delay: 5
      until: consul_leader.status == 200

    - name: Verify Nomad is accessible
      ansible.builtin.uri:
        url: "http://{{ cluster_address }}:4646/v1/status/leader"
        return_content: true
      register: nomad_leader
      retries: 3
      delay: 5
      until: nomad_leader.status == 200

    - name: Get running Nomad jobs
      ansible.builtin.uri:
        url: "http://{{ cluster_address }}:4646/v1/jobs"
        return_content: true
      register: nomad_jobs

    - name: Get Consul services
      ansible.builtin.uri:
        url: "http://{{ cluster_address }}:8500/v1/catalog/services"
        return_content: true
      register: consul_services

    - name: Build running jobs list
      ansible.builtin.set_fact:
        running_jobs: "{{ nomad_jobs.json | selectattr('Status', 'equalto', 'running') | map(attribute='Name') | list }}"

    - name: Display shutdown warning
      ansible.builtin.debug:
        msg: |
          ╔══════════════════════════════════════════════════════════════════╗
          ║                   GRACEFUL CLUSTER SHUTDOWN                     ║
          ╠══════════════════════════════════════════════════════════════════╣
          ║                                                                ║
          ║  This will:                                                    ║
          ║    1. Terraform destroy all services (reverse order)           ║
          ║    2. Set Ceph OSD maintenance flags                           ║
          ║    3. Unmount CephFS on all nodes                              ║
          ║    4. Stop Nomad agents and servers                            ║
          ║    5. Stop Consul agents and servers                           ║
          ║                                                                ║
          ║  Running Nomad jobs ({{ running_jobs | length }}):
          {% for job in running_jobs %}
          ║    - {{ job }}
          {% endfor %}
          ║                                                                ║
          ║  Consul services: {{ consul_services.json | length }}
          ║                                                                ║
          ╚══════════════════════════════════════════════════════════════════╝

    - name: Confirm shutdown
      ansible.builtin.pause:
        prompt: "Type 'yes' to confirm graceful shutdown"
      register: confirm_prompt
      when: confirm_shutdown != "yes"

    - name: Validate confirmation
      ansible.builtin.fail:
        msg: "Shutdown cancelled. User did not confirm."
      when:
        - confirm_shutdown != "yes"
        - confirm_prompt.user_input != "yes"

    - name: Create shutdown state directory
      ansible.builtin.file:
        path: "{{ shutdown_state_dir }}"
        state: directory
        mode: '0700'

    - name: Save pre-shutdown state
      ansible.builtin.copy:
        content: |
          # Octant cluster shutdown state
          # Generated by 08-graceful-shutdown.yml
          timestamp: "{{ ansible_date_time.iso8601 }}"
          running_jobs: {{ running_jobs | to_nice_yaml | indent(2) }}
          consul_services: {{ consul_services.json.keys() | list | to_nice_yaml | indent(2) }}
        dest: "{{ shutdown_state_dir }}/shutdown-state.yml"
        mode: '0600'

  roles:
    - role: apply-terraform
      vars:
        terraform_action: destroy
        modules: "{{ terraform_execution_order | reverse | list }}"
```

- [ ] **Step 2: Add Play 2 (Ceph, Nomad, Consul shutdown)**

Append Play 2 to the same file:

```yaml
- name: Graceful Shutdown - Stop Cluster Services
  hosts: servers
  user: "{{ admin_user }}"
  become: true
  gather_facts: true
  serial: 1
  max_fail_percentage: 0

  tasks:
    # ======================================================================
    # PHASE: Ceph maintenance flags
    # ======================================================================

    - name: Set Ceph OSD maintenance flags
      when: inventory_hostname == groups['servers'][0]
      block:
        - name: Set noout flag
          ansible.builtin.command: ceph osd set noout
          changed_when: true

        - name: Set nobackfill flag
          ansible.builtin.command: ceph osd set nobackfill
          changed_when: true

        - name: Set norecover flag
          ansible.builtin.command: ceph osd set norecover
          changed_when: true

        - name: Verify OSD flags are set
          ansible.builtin.command: ceph osd dump
          register: osd_dump
          changed_when: false

        - name: Display OSD flags
          ansible.builtin.debug:
            msg: "Ceph OSD flags: {{ osd_dump.stdout_lines | select('search', 'flags') | first | default('unable to parse flags') }}"

    # ======================================================================
    # PHASE: Unmount CephFS
    # ======================================================================

    - name: Check if CephFS is mounted
      ansible.builtin.command: mountpoint -q /mnt/services
      register: cephfs_mounted
      changed_when: false
      failed_when: false

    - name: Unmount CephFS
      ansible.posix.mount:
        path: /mnt/services
        state: unmounted
      when: cephfs_mounted.rc == 0

    - name: Verify CephFS is unmounted
      ansible.builtin.command: mountpoint -q /mnt/services
      register: cephfs_verify
      changed_when: false
      failed_when: false

    - name: Confirm unmount
      ansible.builtin.debug:
        msg: "CephFS /mnt/services: {{ 'UNMOUNTED' if cephfs_verify.rc != 0 else 'WARNING - still mounted!' }}"

    # ======================================================================
    # PHASE: Stop Nomad
    # ======================================================================

    - name: Stop nomad-agent
      ansible.builtin.service:
        name: nomad-agent
        state: stopped

    - name: Stop nomad-agent-root
      ansible.builtin.service:
        name: nomad-agent-root
        state: stopped

    - name: Stop nomad-server
      ansible.builtin.service:
        name: nomad-server
        state: stopped

    # ======================================================================
    # PHASE: Stop Consul
    # ======================================================================

    - name: Stop consul-agent
      ansible.builtin.service:
        name: consul-agent
        state: stopped

    - name: Stop consul-agent-root
      ansible.builtin.service:
        name: consul-agent-root
        state: stopped

    - name: Stop consul-server
      ansible.builtin.service:
        name: consul-server
        state: stopped

  post_tasks:
    - name: Display shutdown summary
      ansible.builtin.debug:
        msg: |
          ================================================================================
          GRACEFUL SHUTDOWN COMPLETE - {{ inventory_hostname }}
          ================================================================================

          Services stopped:
            - nomad-agent, nomad-agent-root, nomad-server
            - consul-agent, consul-agent-root, consul-server

          CephFS: {{ 'UNMOUNTED' if cephfs_verify.rc != 0 else 'WARNING - still mounted' }}

          Ceph OSD flags set: noout, nobackfill, norecover

          ================================================================================
          NEXT STEPS
          ================================================================================

          To snapshot VM disks (optional):
            1. Shut down VMs (virsh shutdown octant-01 octant-02 octant-03)
            2. make snapshot

          After restarting the cluster, unset Ceph maintenance flags:
            ssh octant-01 'sudo ceph osd unset noout && \
              sudo ceph osd unset nobackfill && \
              sudo ceph osd unset norecover'

          ================================================================================
```

- [ ] **Step 3: Verify playbook syntax**

Run: `ansible-playbook playbooks/08-graceful-shutdown.yml --syntax-check -i inventory/provisioned_vms.yml -i inventory/groups.yml`
Expected: `playbook: playbooks/08-graceful-shutdown.yml` (no errors)

- [ ] **Step 4: Commit**

```bash
git add playbooks/08-graceful-shutdown.yml
git commit -m "feat: add graceful cluster shutdown playbook

Orchestrates full shutdown sequence: terraform destroy (reverse order),
Ceph OSD flags (noout/nobackfill/norecover), CephFS unmount, stop
Nomad and Consul agents/servers."
```

---

## Chunk 2: Snapshot Playbook

### Task 2: Create the snapshot playbook

**Files:**
- Create: `playbooks/09-snapshot-cluster.yml`

**Reference files (read before starting):**
- `/data/git/eai-cluster/playbooks/92-snapshot-cluster.yml` — reference implementation (adapt for Octant)
- `roles/vm_provision/templates/vm-domain.xml.j2` — VM disk layout (vda=OS qcow2, vdb=data raw, vdc=container raw, sda=cdrom)
- `playbooks/99-teardown.yml` — pattern for hypervisor play with `groups['servers']`

- [ ] **Step 1: Create the snapshot playbook**

Write `playbooks/09-snapshot-cluster.yml`:

```yaml
---
# Cold Snapshot of Cluster VM OS Disks
# Creates external disk snapshots of VM OS disks while VMs are shut off
#
# Usage:
#   make snapshot
#   make snapshot ARGS="-e snapshot_name=pre-upgrade"
#   make snapshot ARGS="-e list_snapshots=true"
#
# Prerequisites:
#   - All cluster VMs must be shut off (run make shutdown first, then shut down VMs)
#
# This playbook:
#   1. Verifies all cluster VMs are shut off
#   2. Saves pre-snapshot domain XML for each VM
#   3. Creates external disk snapshot of OS disk (vda) only
#   4. Skips data disk (vdb, Ceph OSD) and container disk (vdc)
#   5. Verifies overlay file was created
#
# Snapshot mechanism:
#   Uses KVM external snapshots (--disk-only --atomic). The current OS disk
#   becomes a read-only snapshot point. A new qcow2 overlay file is created
#   for future writes. Data and container disks are excluded — application
#   data is backed up via Restic and database dump jobs.
#
# NOTE: This is NON-DESTRUCTIVE to current data. The original OS disk is
#       preserved as read-only. Only post-snapshot writes go to the overlay.

- name: Cold Snapshot of Cluster VM OS Disks
  hosts: hypervisors
  gather_facts: true
  become: true

  vars:
    server_list: "{{ groups['servers'] | default([]) }}"
    snapshot_name: "snapshot-{{ ansible_date_time.iso8601_basic_short }}"
    snapshot_dir: "{{ playbook_dir }}/.snapshots/{{ snapshot_name }}"
    list_snapshots: false

  pre_tasks:
    - name: Display snapshot banner
      ansible.builtin.debug:
        msg: |
          ╔══════════════════════════════════════════════════════════════════╗
          ║              COLD SNAPSHOT - VM OS DISKS                        ║
          ╠══════════════════════════════════════════════════════════════════╣
          ║                                                                ║
          ║  VMs to snapshot:                                              ║
          {% for vm in server_list %}
          ║    - {{ vm }}{{ ' ' * (54 - vm|length) }}║
          {% endfor %}
          ║                                                                ║
          ║  Snapshot name: {{ snapshot_name }}{{ ' ' * (47 - snapshot_name|length) }}║
          ║                                                                ║
          ║  Disks: OS (vda) only                                          ║
          ║  Skipped: data (vdb), container (vdc), cloud-init (sda)        ║
          ║                                                                ║
          ║  Prerequisites: All VMs must be SHUT OFF                       ║
          ╚══════════════════════════════════════════════════════════════════╝
      when: not list_snapshots | bool

  tasks:

    # ======================================================================
    # List snapshots mode
    # ======================================================================

    - name: List existing snapshots
      when: list_snapshots | bool
      block:
        - name: Check for snapshots directory
          ansible.builtin.stat:
            path: "{{ playbook_dir }}/.snapshots"
          register: snapshots_dir_stat
          delegate_to: localhost
          become: false

        - name: Find snapshot metadata files
          ansible.builtin.find:
            paths: "{{ playbook_dir }}/.snapshots"
            patterns: "snapshot-metadata.yml"
            recurse: true
            file_type: file
          register: snapshot_files
          delegate_to: localhost
          become: false
          when: snapshots_dir_stat.stat.exists

        - name: Display available snapshots
          ansible.builtin.debug:
            msg: |
              ================================================================================
              AVAILABLE SNAPSHOTS
              ================================================================================
              {% if not snapshots_dir_stat.stat.exists or (snapshot_files.files | default([]) | length == 0) %}
              No snapshots found.
              {% else %}
              {% for item in snapshot_files.files %}
              Snapshot: {{ item.path | dirname | basename }}
                Directory: {{ item.path | dirname }}
              {% endfor %}
              {% endif %}

              To create a snapshot:
                make snapshot

              ================================================================================

        - name: End play after listing
          ansible.builtin.meta: end_play

    # ======================================================================
    # PHASE 1: Verify all VMs are shut off
    # ======================================================================

    - name: Check VM states
      ansible.builtin.shell: |
        virsh domstate {{ item }} 2>/dev/null
      loop: "{{ server_list }}"
      register: vm_states
      changed_when: false
      failed_when: false

    - name: Verify all VMs are shut off
      ansible.builtin.fail:
        msg: |
          VM {{ item.item }} is in state '{{ item.stdout | trim }}', not 'shut off'.
          All VMs must be shut off before creating a snapshot.
          Run: make shutdown
          Then: virsh shutdown {{ item.item }}
      loop: "{{ vm_states.results }}"
      loop_control:
        label: "{{ item.item }}: {{ item.stdout | trim }}"
      when: item.stdout | trim != 'shut off'

    # ======================================================================
    # PHASE 2: Check for existing snapshot with same name
    # ======================================================================

    - name: Check for existing snapshot directory
      ansible.builtin.stat:
        path: "{{ snapshot_dir }}"
      register: existing_snapshot
      delegate_to: localhost
      become: false

    - name: Fail if snapshot already exists
      ansible.builtin.fail:
        msg: |
          Snapshot '{{ snapshot_name }}' already exists at {{ snapshot_dir }}.
          Choose a different name with: -e snapshot_name=<name>
          Or list existing snapshots with: -e list_snapshots=true
      when: existing_snapshot.stat.exists

    # ======================================================================
    # PHASE 3: Save pre-snapshot state
    # ======================================================================

    - name: Create snapshot metadata directory
      ansible.builtin.file:
        path: "{{ snapshot_dir }}"
        state: directory
        mode: '0700'
      delegate_to: localhost
      become: false

    - name: Export domain XML for each VM
      ansible.builtin.shell: |
        virsh dumpxml {{ item }} > {{ snapshot_dir }}/{{ item }}-domain.xml
      loop: "{{ server_list }}"
      changed_when: true

    - name: Fix ownership of domain XML files
      ansible.builtin.file:
        path: "{{ snapshot_dir }}/{{ item }}-domain.xml"
        owner: "{{ lookup('env', 'USER') }}"
        group: "{{ lookup('env', 'USER') }}"
        mode: '0600'
      loop: "{{ server_list }}"

    - name: Get OS disk path for each VM
      ansible.builtin.shell: |
        virsh domblklist {{ item }} --details 2>/dev/null | awk '$2 == "disk" && $3 == "vda" {print $4}'
      loop: "{{ server_list }}"
      register: os_disk_results
      changed_when: false

    - name: Build OS disk path map
      ansible.builtin.set_fact:
        os_disk_paths: "{{ os_disk_paths | default({}) | combine({item.item: item.stdout | trim}) }}"
      loop: "{{ os_disk_results.results }}"
      loop_control:
        label: "{{ item.item }}: {{ item.stdout | trim }}"

    - name: Display current OS disk paths
      ansible.builtin.debug:
        msg: |
          Current OS disk paths:
          {% for vm in server_list %}
            {{ vm }}: {{ os_disk_paths[vm] }}
          {% endfor %}

    - name: Validate OS disk paths exist
      ansible.builtin.stat:
        path: "{{ os_disk_paths[item] }}"
      loop: "{{ server_list }}"
      loop_control:
        label: "{{ item }}: {{ os_disk_paths[item] }}"
      register: disk_stat_results
      failed_when: not disk_stat_results.stat.exists

    - name: Save snapshot metadata
      ansible.builtin.copy:
        content: |
          # Snapshot metadata - created by 09-snapshot-cluster.yml
          # Do not edit manually
          snapshot_name: "{{ snapshot_name }}"
          timestamp: "{{ ansible_date_time.iso8601 }}"
          server_list: {{ server_list | to_nice_yaml | indent(2) }}
          os_disk_paths:
          {% for vm in server_list %}
            {{ vm }}: "{{ os_disk_paths[vm] }}"
          {% endfor %}
          overlay_paths:
          {% for vm in server_list %}
            {{ vm }}: "{{ os_disk_paths[vm] | dirname }}/{{ vm }}.{{ snapshot_name }}.qcow2"
          {% endfor %}
        dest: "{{ snapshot_dir }}/snapshot-metadata.yml"
        mode: '0600'
        owner: "{{ lookup('env', 'USER') }}"
        group: "{{ lookup('env', 'USER') }}"
      delegate_to: localhost
      become: false

    # ======================================================================
    # PHASE 4: Create external snapshots (OS disk only)
    # ======================================================================

    - name: Discover all disk targets for each VM
      ansible.builtin.shell: |
        virsh domblklist {{ item }} --details 2>/dev/null | awk '$2 == "disk" || $2 == "cdrom" {print $3}'
      loop: "{{ server_list }}"
      register: disk_targets_results
      changed_when: false

    - name: Build non-OS disk exclusion flags
      ansible.builtin.set_fact:
        snapshot_exclude_flags: >-
          {{ snapshot_exclude_flags | default({}) | combine({
            item.item: item.stdout_lines | reject('equalto', 'vda') | map('regex_replace', '^(.*)$', '--diskspec \1,snapshot=no') | join(' ')
          }) }}
      loop: "{{ disk_targets_results.results }}"
      loop_control:
        label: "{{ item.item }}: {{ item.stdout_lines | reject('equalto', 'vda') | list | join(', ') }}"

    - name: Create external OS disk snapshot for each VM
      ansible.builtin.shell: |
        virsh snapshot-create-as {{ item }} \
          "{{ snapshot_name }}" \
          --description "Cold snapshot created by 09-snapshot-cluster.yml" \
          --disk-only \
          --atomic \
          --no-metadata \
          --diskspec vda,snapshot=external,file={{ os_disk_paths[item] | dirname }}/{{ item }}.{{ snapshot_name }}.qcow2 \
          {{ snapshot_exclude_flags[item] }}
      loop: "{{ server_list }}"
      register: snapshot_results
      changed_when: true

    - name: Display snapshot creation results
      ansible.builtin.debug:
        msg: "{{ item.item }}: {{ item.stdout | trim }}"
      loop: "{{ snapshot_results.results }}"
      loop_control:
        label: "{{ item.item }}"

    # ======================================================================
    # PHASE 5: Verify overlay files were created
    # ======================================================================

    - name: Verify OS disk overlay files exist
      ansible.builtin.stat:
        path: "{{ os_disk_paths[item] | dirname }}/{{ item }}.{{ snapshot_name }}.qcow2"
      loop: "{{ server_list }}"
      register: overlay_check
      failed_when: not overlay_check.stat.exists

    - name: Verify VM definitions now point to overlay files
      ansible.builtin.shell: |
        virsh domblklist {{ item }} --details 2>/dev/null | awk '$2 == "disk" && $3 == "vda" {print $3, $4}'
      loop: "{{ server_list }}"
      register: post_snapshot_disks
      changed_when: false

    - name: Display post-snapshot disk assignments
      ansible.builtin.debug:
        msg: |
          Post-snapshot OS disk assignments:
          {% for result in post_snapshot_disks.results %}
            {{ result.item }}:
          {{ result.stdout | indent(6, true) }}
          {% endfor %}

  post_tasks:
    - name: Display snapshot summary
      ansible.builtin.debug:
        msg: |
          ================================================================================
          SNAPSHOT CREATED SUCCESSFULLY
          ================================================================================

          Snapshot: {{ snapshot_name }}
          Timestamp: {{ ansible_date_time.iso8601 }}
          Scope: OS disk (vda) only

          Metadata saved to: {{ snapshot_dir }}/
          {% for vm in server_list %}
            - {{ vm }}-domain.xml
          {% endfor %}
            - snapshot-metadata.yml

          Overlay files created:
          {% for vm in server_list %}
            {{ vm }}: {{ os_disk_paths[vm] | dirname }}/{{ vm }}.{{ snapshot_name }}.qcow2
          {% endfor %}

          Original OS disks (now read-only snapshot points):
          {% for vm in server_list %}
            {{ vm }}: {{ os_disk_paths[vm] }}
          {% endfor %}

          ================================================================================
          NEXT STEPS
          ================================================================================

          Start cluster (VMs auto-start Ceph, Consul, Nomad via systemd):
            virsh start octant-01 && virsh start octant-02 && virsh start octant-03

          After cluster is healthy, unset Ceph maintenance flags:
            ssh octant-01 'sudo ceph osd unset noout && \
              sudo ceph osd unset nobackfill && \
              sudo ceph osd unset norecover'

          List all snapshots:
            make snapshot ARGS="-e list_snapshots=true"

          ================================================================================
```

- [ ] **Step 2: Verify playbook syntax**

Run: `ansible-playbook playbooks/09-snapshot-cluster.yml --syntax-check -i inventory/hypervisors.yml -i inventory/groups.yml`
Expected: `playbook: playbooks/09-snapshot-cluster.yml` (no errors)

- [ ] **Step 3: Commit**

```bash
git add playbooks/09-snapshot-cluster.yml
git commit -m "feat: add cold snapshot playbook for VM OS disks

Creates external qcow2 snapshots of OS disks (vda) only while VMs
are shut off. Skips data (Ceph OSD) and container disks — application
data is backed up via Restic and database dump jobs."
```

---

## Chunk 3: Makefile & Gitignore

### Task 3: Add Makefile targets and gitignore entries

**Files:**
- Modify: `Makefile`
- Modify: `.gitignore`

- [ ] **Step 1: Update `.PHONY` declaration**

In `Makefile` line 5, add `shutdown snapshot` to the end of the `.PHONY` list. The updated line should be:

```makefile
.PHONY: run run-flush-cache lint check-env build-base-image provision-vms deploy-cluster deploy-haproxy remove-haproxy deploy-ceph deploy-volumes deploy-services destroy-services health-check capture-state deploy-vm teardown rebuild clear-secrets install-hashi-cli podman-cleanup docs docs-publish shutdown snapshot
```

- [ ] **Step 2: Add shutdown and snapshot targets to Makefile**

Add between line 176 (`ansible-playbook playbooks/podman-cleanup.yml $(VM_CLUSTER_INVENTORY)`) and line 178 (`# --- Documentation ---`), replacing the blank line 177:

```makefile

# --- Cluster Lifecycle ---
shutdown:
	ansible-playbook playbooks/08-graceful-shutdown.yml $(VM_CLUSTER_INVENTORY) $(ARGS)

snapshot:
	ansible-playbook playbooks/09-snapshot-cluster.yml -i inventory/hypervisors.yml -i inventory/groups.yml $(ARGS)

```

**NOTE:** The snapshot target includes `-i inventory/groups.yml` because the playbook references
`groups['servers']` to determine which VMs to snapshot. This differs from the spec's Makefile
example which omitted it — the spec has been updated to match.

- [ ] **Step 2: Add gitignore entries for runtime artifacts**

Append to `.gitignore`:

```
playbooks/.shutdown-state/
playbooks/.snapshots/
```

- [ ] **Step 3: Verify make targets are recognized**

Run: `make -n shutdown` (dry run)
Expected: Shows the ansible-playbook command without executing

Run: `make -n snapshot` (dry run)
Expected: Shows the ansible-playbook command without executing

- [ ] **Step 4: Commit**

```bash
git add Makefile .gitignore
git commit -m "feat: add make shutdown and snapshot targets

Adds convenience targets for graceful cluster shutdown and VM OS disk
snapshots. Gitignores runtime state directories."
```
