# Nomad Spread Scheduler Configuration

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the Nomad `spread` scheduler algorithm permanent in IaC so cluster rebuilds preserve even workload distribution.

**Architecture:** The Nomad scheduler algorithm is a cluster-wide runtime setting configured via the API (`nomad operator scheduler set-config`), not a server config file directive. We add an Ansible task to `octant.yml` post_tasks that sets it after all Nomad servers are confirmed running. This runs `run_once: true` since it's a cluster-wide setting.

**Tech Stack:** Ansible, Nomad CLI

---

## Background

The Nomad scheduler has two algorithms:
- **`binpack`** (default): Optimizes resource utilization by packing allocations onto fewer nodes. Good for cloud cost savings, bad for homelab resilience — resulted in 29/33 allocs on a single node.
- **`spread`**: Distributes allocations evenly across available nodes. Better for fault tolerance in a fixed-size cluster.

The setting was changed live via `nomad operator scheduler set-config -scheduler-algorithm=spread` but needs to be codified in Ansible.

---

### Task 1: Add scheduler configuration to octant.yml post_tasks

**Files:**
- Modify: `octant.yml:79-95` (post_tasks section)

**Step 1: Add the scheduler config task**

Add a new task at the end of the `post_tasks` block in `octant.yml`, after the existing service health checks. This task runs the `nomad operator scheduler set-config` command once across the cluster after all Nomad servers are confirmed running:

```yaml
    - name: Set Nomad scheduler algorithm to spread
      ansible.builtin.command:
        cmd: nomad operator scheduler set-config -scheduler-algorithm=spread
      environment:
        NOMAD_ADDR: "http://localhost:{{ nomad.ports.http }}"
      register: scheduler_config
      changed_when: "'updated' in scheduler_config.stdout"
      run_once: true
```

This goes after the existing `Ensure service are running` loop (line 95).

**Step 2: Verify the playbook syntax**

Run: `ansible-playbook --syntax-check octant.yml -i inventory/groups.yml`
Expected: `playbook: octant.yml` (no errors)

**Step 3: Commit**

```bash
git add octant.yml
git commit -m "feat(nomad): set scheduler algorithm to spread in post_tasks

Nomad defaults to binpack which packs all allocations onto one node.
For a fixed 3-node homelab, spread distributes workloads evenly for
better fault tolerance. This is a cluster-wide runtime API setting
that must be applied after servers are running."
```

---

### Task 2: Verify the live cluster state

**Step 1: Confirm the scheduler config is active**

Run: `nomad operator scheduler get-config`
Expected: `Scheduler Algorithm = spread`

**Step 2: Check current allocation distribution**

Run: `nomad alloc status -t '{{range .}}{{.NodeID | printf "%.8s"}} {{.ClientStatus}}{{"\n"}}{{end}}' | grep running | awk '{print $1}' | sort | uniq -c | sort -rn`

Note: Existing allocations won't rebalance automatically. New job submissions or restarts will use the spread algorithm. To force rebalancing, jobs would need to be stopped and restarted — but this is disruptive and not recommended as part of this change.
