# Volumes Role Port & Related Fixes

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Port the `roles/volumes/` role from octant-private, create an independent volumes playbook, fix the weaviate path typo, and document octant-private remediation items.

**Architecture:** The volumes role is a single-source-of-truth for creating service directories on CephFS with per-volume permission overrides. It replaces the inline `post_tasks` block in `02-deploy-ceph.yml`. A standalone `playbooks/05-deploy-volumes.yml` playbook allows volumes to be managed independently (e.g., when adding new apps) and is also called from the Ceph playbook to preserve the existing deployment flow.

**Tech Stack:** Ansible roles, YAML inventory, Nomad HCL, Make

---

### Task 1: Create the volumes role

**Files:**
- Create: `roles/volumes/defaults/main.yml`
- Create: `roles/volumes/tasks/main.yml`

**Step 1: Create role defaults**

```yaml
---
# Default ownership and permissions for service volumes
# These defaults can be overridden per-volume in inventory

# Default user/group ownership
volume_default_owner: "{{ user | default('hashi') }}"
volume_default_group: "{{ group | default('hashi') }}"

# Default directory permissions
volume_default_mode: "0755"

# Whether to manage permissions for volumes
# Set to false for container-managed volumes (e.g., homeassistant subdirs)
volume_manage_permissions: true
```

Note: dropped `volume_strict_validation` from octant-private — it's defined but never used.

**Step 2: Create role tasks**

```yaml
---
# Volume management role - Single source of truth for service volume creation
# Volumes are defined in inventory/groups.yml with optional custom permissions

- name: Create service volume directories
  ansible.builtin.file:
    path: "{{ item.path }}"
    state: directory
    owner: "{{ item.owner | default(volume_default_owner) }}"
    group: "{{ item.group | default(volume_default_group) }}"
    mode: "{{ item.mode | default(volume_default_mode) }}"
  loop: "{{ volumes }}"
  loop_control:
    label: "{{ item.name }}: {{ item.path }}"
  when: item.manage_permissions | default(volume_manage_permissions) | bool

- name: Report volumes with manage_permissions=false
  ansible.builtin.debug:
    msg: "Skipping permission management for {{ item.name }} ({{ item.path }}) - managed by container"
  loop: "{{ volumes }}"
  loop_control:
    label: "{{ item.name }}"
  when:
    - not (item.manage_permissions | default(volume_manage_permissions) | bool)
    - ansible_verbosity >= 1
```

Note: dropped the `/mnt/services` parent directory task from octant-private — in this worktree, `/mnt/services` is the CephFS mount point managed by the ceph role. Creating it here would interfere with mount detection.

**Step 3: Commit**

```
feat: add volumes role ported from octant-private

Supports per-volume owner, group, mode, and manage_permissions overrides.
```

---

### Task 2: Create standalone volumes playbook

**Files:**
- Create: `playbooks/05-deploy-volumes.yml`
- Modify: `playbooks/02-deploy-ceph.yml` (remove post_tasks, add import)
- Modify: `Makefile` (add deploy-volumes target, update deploy-vm chain)

**Step 1: Create the volumes playbook**

```yaml
---
# Deploy service volume directories on CephFS
# Can be run independently to add volumes for new apps
#
# Usage:
#   make deploy-volumes
#   ansible-playbook playbooks/05-deploy-volumes.yml -i inventory/provisioned_vms.yml -i inventory/groups.yml
#
# Prerequisites:
#   - CephFS mounted at /mnt/services (via playbooks/02-deploy-ceph.yml)

- name: Deploy service volumes
  hosts: servers
  gather_facts: false
  become: true
  roles:
    - role: volumes
      tags: volumes
```

**Step 2: Update 02-deploy-ceph.yml — replace post_tasks with playbook import**

Remove lines 51-60 (the `post_tasks` block) and replace with an import of the volumes playbook:

```yaml
# After the "Deploy Ceph Storage Cluster" play, add:
- name: Deploy service volumes on CephFS
  ansible.builtin.import_playbook: 05-deploy-volumes.yml
```

The final file should be:

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

- name: Prepare nodes for Ceph deployment
  hosts: servers
  gather_facts: true
  become: true
  tasks:
    - name: Fix /etc/hosts so hostname -f returns the actual hostname
      ansible.builtin.lineinfile:
        path: /etc/hosts
        regexp: '^127\.0\.0\.1'
        line: "127.0.0.1 {{ inventory_hostname }} localhost localhost.localdomain"

    - name: Add peer host entries to /etc/hosts
      ansible.builtin.lineinfile:
        path: /etc/hosts
        regexp: ".*{{ item }}$"
        line: "{{ hostvars[item].ansible_host | default(hostvars[item].ansible_default_ipv4.address) }} {{ item }}"
      loop: "{{ groups['servers'] | difference([inventory_hostname]) }}"

    - name: Enable root SSH login for cephadm
      ansible.builtin.lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^PermitRootLogin'
        line: 'PermitRootLogin prohibit-password'
      notify: restart sshd

  handlers:
    - name: restart sshd
      ansible.builtin.service:
        name: sshd
        state: restarted

- name: Deploy Ceph Storage Cluster
  hosts: servers
  gather_facts: true
  become: true
  roles:
    - role: ceph

- name: Deploy service volumes on CephFS
  ansible.builtin.import_playbook: 05-deploy-volumes.yml
```

**Step 3: Add Makefile target**

After the `deploy-ceph` target (line 120), add:

```makefile
deploy-volumes:
	ansible-playbook playbooks/05-deploy-volumes.yml $(VM_CLUSTER_INVENTORY)
```

Update the `deploy-vm` chain (line 131) to include `deploy-volumes`:

```makefile
deploy-vm: build-base-image provision-vms deploy-cluster deploy-ceph deploy-services health-check
```

Note: `deploy-volumes` does NOT need to be added to the `deploy-vm` chain because `deploy-ceph` already imports the volumes playbook. The standalone target is for adding volumes after initial deployment.

Update `.PHONY` (line 5) to include `deploy-volumes`.

**Step 4: Commit**

```
feat: add standalone volumes playbook, integrate into ceph deploy

05-deploy-volumes.yml can run independently for adding new app volumes.
02-deploy-ceph.yml imports it automatically after CephFS mount.
```

---

### Task 3: Add postgres-data permissions to inventory

**Files:**
- Modify: `inventory/groups.yml` (add mode to postgres-data)
- Modify: `inventory/groups.yml.example` (same change)

**Step 1: Update postgres-data volume definition**

In `inventory/groups.yml`, change the postgres-data entry from:

```yaml
      - name: postgres-data
        path: /mnt/services/postgres
        backup: true
```

to:

```yaml
      - name: postgres-data
        path: /mnt/services/postgres
        backup: true
        mode: "0700"
```

Apply the same change to `groups.yml.example`.

**Step 2: Commit**

```
fix: set postgres-data volume to mode 0700

PostgreSQL requires restrictive permissions on its data directory.
Matches octant-private configuration.
```

---

### Task 4: Fix weaviate path typo

**Files:**
- Modify: `inventory/groups.yml` (fix paths on lines 91, 94)
- Modify: `inventory/groups.yml.example` (fix paths on lines 91, 94)
- Modify: `terraform/weaviate/weviate.nomad.hcl` (fix path on line 91)
- Rename: `terraform/weaviate/weviate.nomad.hcl` → `terraform/weaviate/weaviate.nomad.hcl`

**Step 1: Fix inventory paths**

In `groups.yml` and `groups.yml.example`, change:

```yaml
      - name: weaviate-config
        path: /mnt/services/weviate/config
        backup: true
      - name: weaviate-data
        path: /mnt/services/weviate/data
        backup: false
```

to:

```yaml
      - name: weaviate-config
        path: /mnt/services/weaviate/config
        backup: true
      - name: weaviate-data
        path: /mnt/services/weaviate/data
        backup: false
```

**Step 2: Fix terraform volume path and rename file**

In `terraform/weaviate/weviate.nomad.hcl` line 91, change:

```hcl
        volumes = ["/mnt/services/weviate/data:/var/lib/weaviate"]
```

to:

```hcl
        volumes = ["/mnt/services/weaviate/data:/var/lib/weaviate"]
```

Then rename the file:

```bash
git mv terraform/weaviate/weviate.nomad.hcl terraform/weaviate/weaviate.nomad.hcl
```

**Step 3: Update terraform module reference if needed**

Check `terraform/weaviate/main.tf` or any file that references `weviate.nomad.hcl` by filename. Terraform `templatefile()` or `file()` calls will need updating.

**Step 4: Commit**

```
fix: correct weaviate path typo (weviate -> weaviate)

Fixes inventory paths, nomad job volume mount, and HCL filename.
```

---

### Task 5: Document octant-private remediation items

**Files:**
- Create: `docs/plans/2026-02-24-octant-private-volume-remediation.md`

**Step 1: Write the remediation plan**

This is a documentation-only task. The file should cover:

1. **Weaviate path typo** — same fix as Task 4 but in octant-private's inventory and terraform
2. **pgadmin volume commented out** — `terraform/pgadmin/pgadmin.nomad.hcl` line 58 has the volume mount commented out; pgadmin data is ephemeral
3. **musicassistant volume mismatch** — terraform mounts `/mnt/services/musicassistant` but inventory only defines subdirectories (`.cache`, `playlists`); needs a parent volume entry or the mount path should reference the subdirs

See Task 5 content below for the exact file.

**Step 2: Commit**

```
docs: add octant-private volume remediation plan
```

---

### Task 6: Verify and commit all changes

**Step 1: Validate ansible syntax**

```bash
cd /home/melliott/git/octant/.worktrees/vm-deployment
ansible-playbook playbooks/05-deploy-volumes.yml --syntax-check $(VM_CLUSTER_INVENTORY)
ansible-playbook playbooks/02-deploy-ceph.yml --syntax-check $(VM_CLUSTER_INVENTORY)
```

Note: syntax-check may fail without real inventory connectivity — that's OK. The goal is to catch YAML/Jinja2 parse errors.

**Step 2: Verify terraform references**

```bash
grep -r "weviate" terraform/ inventory/
```

Expected: no results (all instances fixed).

**Step 3: Verify volume role is discoverable**

```bash
ls roles/volumes/defaults/main.yml roles/volumes/tasks/main.yml
```

Expected: both files exist.
