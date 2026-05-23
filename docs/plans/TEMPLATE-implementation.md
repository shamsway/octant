# [Feature/Change Name] Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** One sentence restating the objective from the design doc.

**Architecture:** Brief summary of how the pieces fit together — enough context to implement without re-reading the design doc.

**Tech Stack:** Comma-separated list of tools/technologies involved (e.g., Ansible, Terraform, Nomad HCL, 1Password CLI, Consul, Podman, CephFS)

**Reference:** Links to source material — design doc, octant-private paths, external docs.

---

### Task 1: [Short imperative description]

[Optional context paragraph explaining why this task exists or any non-obvious decisions.]

**Files:**
- Create: `path/to/new/file.tf`
- Modify: `path/to/existing/file.yml:line-range`
- Rename: `old/path` -> `new/path`

**Step 1: [Action verb] [what]**

Description of what to do. Include code blocks showing the exact target state:

```yaml
# Show the exact content or diff, not pseudocode
key: value
```

**Step 2: [Action verb] [what]**

Continue with sequential steps. For modifications, show both before and after when helpful:

```hcl
# Before
old_value = "something"

# After
new_value = "something_else"
```

**Step N: Commit**

```bash
git add specific/files/changed
git commit -m "type(scope): short description

Longer explanation of what changed and why."
```

---

### Task 2: [Short imperative description]

**Files:**
- ...

**Step 1: ...**

[Continue pattern. Each task should be independently committable.]

---

### Task N: Deploy and verify

[Final task is typically deployment and verification — may be manual.]

**Step 1: Apply changes**

```bash
make deploy-services
# or
cd terraform/module && terraform init && terraform apply -auto-approve
```

**Step 2: Verify**

```bash
# Commands to confirm the change worked
ssh admin@192.168.122.101 'command to check'
```

Expected: [What the output should look like.]

**Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix: deployment fixes from testing"
```

---

### Task N+1: Update progress tracker

**Files:**
- Modify: `docs/plans/2026-02-21-vm-deployment-progress.md`

**Step 1: Update relevant sections**

Add entries reflecting the completed work.

**Step 2: Commit**

```bash
git add docs/plans/
git commit -m "docs: update progress tracker with [feature] status"
```
