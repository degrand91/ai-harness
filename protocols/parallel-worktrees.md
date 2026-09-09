# Protocol: Parallel Worktree Execution

> **Status: SUPERSEDED.**
>
> Superseded by [crew.md](crew.md), which is how worktree isolation actually works now:
> a crewmate is a separate process in its own worktree, always — not an opt-in mode.
> The concurrency this document describes remains **banned**; see [serial-execution.md](serial-execution.md).
> Kept for the dependency-graph reasoning, which still applies if the limit is ever raised.

Serial execution is the default. This protocol describes the **opt-in** extension that allows independent features to run concurrently via git worktrees. Read [serial-execution.md](serial-execution.md) first — every rule there still applies unless explicitly overridden here.

---

## When to use

The Orchestrator may activate parallel mode when **all** of the following conditions are true:

1. The mission has **4 or more features** remaining (overhead is not worth it below this threshold).
2. At least two features declare **no dependencies on each other** in their `spec.md` `## Dependencies` field.
3. The features do not edit overlapping files (verified by inspecting their `## Scope` sections).
4. The mission's Phase 1 reliability baseline (all prior features green) is in place.

The Orchestrator builds a **dependency graph (DAG)** from the `dependencies` field in each feature spec. Features that share no path through the DAG are candidates for concurrent execution.

---

## How it works

### 1. Spawn Workers with isolation

For each feature in an independent subgraph, spawn a Worker using `isolation: "worktree"` in the Agent tool call:

```
subagent_type: "worker"
model: "sonnet"
isolation: "worktree"
description: "Worker — F003 add-cache-layer (parallel)"
prompt: <feature spec> + <contract slice>
```

Claude Code creates a temporary git worktree branched from HEAD for each Worker. The Worker operates entirely inside its own worktree — it cannot see or touch another Worker's in-progress changes.

### 2. Worktree lifecycle

- **On spawn**: A new branch is created from HEAD (e.g. `worktree/f003-add-cache-layer`). The Worker checks out into a temporary directory.
- **On completion with changes**: The branch and its path are returned to the Orchestrator in the handoff.
- **On completion with no changes**: The worktree is automatically cleaned up by the runtime. No branch is left behind.
- **On failure**: The Orchestrator discards the branch and re-spawns or opens a follow-up feature.

### 3. Concurrency limit

Run at most **3 Worker subagents concurrently** by default. This limit prevents context-window saturation and keeps the merge surface manageable. If a mission warrants more, document the exception in `plan.md`.

### 4. Validator serialization

Validators always run **one at a time per feature**, even in parallel mode. The sequence per feature is:

```
Worker completes → Scrutiny Validator → (User-Testing Validator if applicable) → Orchestrator decides
```

Scrutiny for feature N does NOT block the Worker running feature M if N and M are independent. But the Orchestrator must wait for N's full validation cycle before merging N's branch.

### 5. Merge strategy

After all parallel Workers complete and pass validation, merge their branches into `main` sequentially:

```bash
git merge --no-ff worktree/f003-add-cache-layer
git merge --no-ff worktree/f005-add-metrics
```

Merge order: follow the original feature numbering (lower numbers first) to preserve a readable history.

**On merge conflict**: The Orchestrator attempts auto-resolution for non-overlapping hunks. If a conflict cannot be cleanly resolved:
1. Discard the conflicting branch (`git merge --abort`).
2. Open a follow-up feature scoped to re-implementing the conflicting portion on top of the merged codebase.
3. Do not silently patch — record the conflict in `log.md`.

---

## When NOT to use

Parallel mode must **not** be activated when:

- Any two candidate features declare overlapping files in their `## Scope` section.
- A feature produces an artifact (file, schema, type) that another candidate feature reads or imports.
- The mission has fewer than 4 remaining features.
- Phase 1 reliability fixes are not yet applied (the green baseline does not exist).
- The Orchestrator is uncertain about the dependency graph — when in doubt, serialize.

---

## Relationship to serial-execution.md

[serial-execution.md](serial-execution.md) remains the governing document for all execution decisions. Parallel mode is an **addendum**, not a replacement. Specifically:

- The ban on running two Workers against the **same file** is absolute. Worktrees provide isolation, not permission to conflict.
- Validators never run concurrently across different features.
- Explorer subagents may still run in parallel during planning regardless of whether parallel mode is on.
- The Orchestrator still owns `status.json` and `log.md`; Workers in worktrees do not write to the mission folder directly.

---

## Checklist for activating parallel mode

Before spawning parallel Workers, confirm:

- [ ] Mission has 4+ features remaining.
- [ ] Dependency DAG is written and reviewed.
- [ ] No candidate features share files in their `## Scope`.
- [ ] All prior features are green.
- [ ] Concurrency cap (3) is not exceeded.
- [ ] `plan.md` notes that parallel mode is active.
