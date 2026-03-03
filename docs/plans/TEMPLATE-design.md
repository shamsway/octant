# [Feature/Change Name] - Design

**Date:** YYYY-MM-DD
**Branch:** `feature/branch-name`
**Status:** Draft | Approved

## Goal

One sentence stating what this design achieves and why.

## Context

Brief background: what exists today, what problem this solves, and any relevant prior work (branches, PRDs, external repos like octant-private).

## Architecture

```
ASCII diagram showing the system/data flow.
Include relevant IPs, ports, paths, and service names.
```

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Decision point 1 | What was chosen | Why |
| Decision point 2 | What was chosen | Why |

## What Gets Changed

Describe the components affected. Use tables for inventories:

| Component | Current State | Target State | Notes |
|-----------|--------------|--------------|-------|
| component-1 | ... | ... | ... |
| component-2 | ... | ... | ... |

## Implementation Sections

Break the design into logical phases or numbered sections. Each section should cover a coherent unit of work.

### Section 1: [Name]

Describe what this section covers. Include:

- File paths and what changes in each
- Configuration snippets (YAML, HCL, etc.) showing the target state
- Any new roles, modules, or scripts being created
- How this section integrates with existing infrastructure

### Section 2: [Name]

Continue with additional sections as needed.

## Non-Goals

- Things explicitly out of scope for this design
- Work deferred to later phases
- Related changes that belong in a separate PRD

## Validation

How to verify the design works after implementation:

- Key commands to run
- Expected outputs or states
- Health checks or service registrations to confirm
