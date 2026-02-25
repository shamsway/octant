# Octant Repo Restructuring Design

## Problem

The Octant project has two deployment methods on diverging branches:

- **Bare-metal** (main branch): Targets physical servers with NFS, Tailscale, direct SSH. Entry point: `homelab.yml`.
- **VM deployment** (feature/app-migration): Targets KVM/libvirt VMs with CephFS, HAProxy, cloud-init. Entry point: numbered playbook pipeline.

The feature branch has ~60 commits with shared improvements (terraform modules, 1Password, Nomad fixes), potentially breaking changes (renames, path changes), and VM-specific automation. These need to be merged without breaking bare-metal deployment.

## Decisions

| Question | Decision |
|----------|----------|
| Project trajectory | Both paths are active. Bare-metal runs production, VM is parallel lab/dev. |
| Rebrand (homelab → octant) | Do it on main, independent of VM work. |
| Makefile design | `deploy` stays bare-metal. VM gets `vm-*` prefixed targets. |
| Terraform state | Keep Consul backend. |
| Path migration (/opt/homelab → /opt/octant) | Document as manual step on existing servers. |

## Chosen Approach: Monorepo with Directory-Based Separation

Merge everything to main. Separation between deployment methods is expressed through entry points, not directory trees:

- Bare-metal enters via `octant.yml` at the root
- VMs enter via `playbooks/site.yml`
- Shared roles and terraform modules are consumed by both

### Repository Organization

```
octant/
├── octant.yml                          # Bare-metal entry point
├── Makefile                            # deploy (baremetal) + vm-* (VM)
├── envrc.example
├── ansible.cfg
│
├── roles/                              # All roles, shared and VM-specific
│   ├── requirements/                   # Shared
│   ├── tailscale/                      # Shared
│   ├── consul-server/                  # Shared
│   ├── consul-agent/                   # Shared
│   ├── consul-agent-root/              # Shared
│   ├── nomad-server/                   # Shared
│   ├── nomad-agent/                    # Shared
│   ├── nomad-agent-root/               # Shared
│   ├── install-hashi/                  # Shared
│   ├── configure-consul/               # Shared
│   ├── configure-nomad/                # Shared
│   ├── podman-root/                    # Shared
│   ├── podman-rootless/                # Shared
│   ├── docker/                         # Shared
│   ├── restic/                         # Shared
│   ├── server-update/                  # Shared
│   ├── secrets/                        # Shared (new)
│   ├── seed-onepassword/               # Shared (new)
│   ├── apply-terraform/                # Shared (new)
│   ├── volumes/                        # Shared (new)
│   ├── vm_provision/                   # VM-only
│   ├── vm_storage/                     # VM-only
│   ├── ceph/                           # VM-only
│   ├── container-storage/              # VM-only
│   └── haproxy/                        # VM-only
│
├── terraform/                          # All modules (shared)
│   ├── traefik/
│   ├── postgres/
│   ├── ...30+ modules...
│   ├── dns-lab/                        # VM-specific DNS
│   └── op/                             # 1Password integration
│
├── playbooks/                          # VM deployment pipeline
│   ├── site.yml
│   ├── 00-build-base-image.yml
│   ├── 01-provision-vms.yml
│   ├── 02-deploy-ceph.yml
│   ├── 02.5-deploy-haproxy.yml
│   ├── 02.5-remove-haproxy.yml
│   ├── 03-deploy-services.yml
│   ├── 04-health-check.yml
│   ├── 05-deploy-volumes.yml
│   ├── 06-destroy-services.yml
│   ├── 99-teardown.yml
│   ├── install-hashi-cli.yml
│   └── podman-cleanup.yml
│
├── inventory/
│   ├── groups.yml.example              # Bare-metal template
│   ├── hypervisors.yml.example         # VM hypervisor template
│   └── group_vars/
│       └── all.yml.example             # Global vars (both paths)
│
├── scripts/
│   ├── generate-secrets.sh
│   ├── clear-vault-secrets.sh
│   └── seed-1password-vault.sh
│
├── packer/                             # Image building
├── docs/
├── handlers/main.yml
├── *.yml                               # Bare-metal utility playbooks
└── README.md
```

### Makefile Design

Three sections: shared, bare-metal, VM.

```makefile
# ============================================================================
# Configuration
# ============================================================================
INVENTORY         := -i inventory/groups.yml
VM_INVENTORY      := -i inventory/hypervisors.yml -i inventory/groups.yml
VM_CLUSTER_INV    := -i inventory/provisioned_vms.yml -i inventory/groups.yml

# ============================================================================
# Bare-Metal Deployment (make deploy)
# ============================================================================
deploy:              # ansible-playbook octant.yml $(INVENTORY)
deploy-verbose:      # deploy with -vvv
deploy-host:         # Deploy to specific HOST=
deploy-role:         # Deploy specific ROLE= by tag
deploy-role-host:    # Deploy ROLE= to HOST=

# (all existing consul/nomad/nfs/gcp targets preserved exactly)

# ============================================================================
# VM Deployment (make vm-*)
# ============================================================================
vm-build-image:      # Build base VM image
vm-provision:        # Provision VMs from base image
vm-deploy-cluster:   # Run octant.yml on VMs
vm-deploy-ceph:      # Bootstrap Ceph cluster
vm-deploy-haproxy:   # Deploy HAProxy ingress
vm-remove-haproxy:   # Remove HAProxy
vm-deploy-volumes:   # Create service volumes
vm-deploy-services:  # Seed 1Password + terraform apply
vm-destroy-services: # Terraform destroy in reverse
vm-health-check:     # Cluster health validation
vm-seed-secrets:     # Run seed-onepassword only
vm-fresh-deploy:     # Full pipeline: image → VMs → cluster → ceph → haproxy → services → health
vm-deploy:           # Refresh: provision → cluster → ceph → haproxy → services → health
vm-teardown:         # Interactive teardown
vm-teardown-force:   # Auto-approved teardown
vm-install-cli:      # Install consul/nomad CLIs on hypervisor
vm-podman-cleanup:   # Clean dangling containers

# ============================================================================
# Shared
# ============================================================================
tf-apply-gcp:        tf-destroy-gcp:       tf-update-dns:
tf-update-dns-lab:   tf-destroy-dns-lab:   lint:
```

## Migration Plan

### Phase 1: Rebrand (standalone commit on main)

1. Rename `homelab.yml` → `octant.yml`
2. Update all `/opt/homelab/` → `/opt/octant/` in group_vars, roles, templates
3. Update Makefile to reference `octant.yml`
4. Update README

**Bare-metal users must:** Run `mv /opt/homelab /opt/octant` on each existing server before the next deploy.

### Phase 2: Merge shared improvements

Cherry-pick or merge from feature/app-migration:

1. New terraform modules (alertmanager, alloy, tempo, gatus, dns-lab, op, etc.)
2. Upgraded terraform modules (stubs → full main.tf + variables.tf)
3. New shared roles: secrets, seed-onepassword, apply-terraform, volumes
4. 1Password integration in terraform modules
5. Nomad job spec fixes (userns mapping, container storage, connect block removal)
6. Traefik v3 config fixes (TLS nesting, field names, consul catalog provider)
7. scripts/ directory
8. ansible.cfg
9. Updated group_vars/all.yml.example (additive, keep bare-metal defaults)
10. SSH user: `matt` → `{{ admin_user | default('matt') }}`

**What NOT to merge:**
- DNS defaults changed to VM IPs (keep 192.168.1.x bare-metal defaults)
- Redefinition of `make deploy` to VM pipeline

### Phase 3: Merge VM-specific automation

1. Add playbooks/ directory with full 00-99 pipeline
2. Add VM-specific roles: vm_provision, vm_storage, ceph, container-storage, haproxy
3. Add inventory/hypervisors.yml.example
4. Extend groups.yml.example with VM host vars (as comments)
5. Add vm-* targets to Makefile
6. Add packer/ updates

### Phase 4: Documentation and cleanup

1. Update README with dual deployment docs
2. Clean up remaining old references
3. Delete feature/app-migration branch

## Risk Assessment

| Step | Risk | Impact | Mitigation |
|------|------|--------|------------|
| Rename homelab.yml → octant.yml | Low | make deploy breaks until Makefile updated | Same commit |
| /opt/homelab/ → /opt/octant/ | Medium | Servers have data at old paths | Document manual mv step |
| SSH user matt → {{ admin_user }} | Low | Connection fails if unset | Default to 'matt' |
| Merging role changes | Medium | Behavior change on bare-metal | Diff each role. Test with --check --diff |
| container-storage in octant.yml | Medium | Checks /dev/vdc on bare-metal | Verify `when:` guard exists |
| group_vars changes | Low | New required vars break deploy | Use default() filters |
| Adding playbooks/ | None | Purely additive | — |
| Adding VM Makefile targets | None | Purely additive | — |

## Alternatives Considered

**B: Monorepo with deploy/ namespacing** — VM roles under deploy/vm/roles/. Cleaner separation but adds Ansible roles_path complexity. Rejected: not worth the config overhead.

**C: Merge as-is with naming convention** — Just merge and use vm- prefix on role names. Rejected: least discoverable, naming is the only signal.

**A (long-lived branch):** Cherry-pick burden grows, shared code drifts. Rejected.

**Separate repo:** Submodule/subtree complexity for shared code. Rejected.
