---
name: dispatch
description: Put the next pending feature into execution — as a crewmate in its own worktree, or as an in-process worker. Use when a mission is executing and the previous feature has closed, or when the turn-end guard says the loop ended blind.
argument-hint: [mission-id] [feature-id]
allowed-tools: Bash(./scripts/feature-dispatch.sh *), Bash(./scripts/fleet.sh), Bash(./scripts/crew/*), Bash(./scripts/hold.sh *), Read, Write, Edit, Agent
---

## Fleet

!`${CLAUDE_PROJECT_DIR}/scripts/fleet.sh`

---

Dispatch **one** feature. If `$ARGUMENTS` names a mission and feature, use those; otherwise take the executing mission and its first `pending` feature.

### 1. Check before you dispatch

```
./scripts/feature-dispatch.sh <mission> <feature> --dry-run --intent - --done -
```

It tells you the execution model, the project and the delivery mode. It **refuses** — and says what to do instead — when the mission is not executing, a blocking decision is open, the feature is not pending, the concurrency limit is reached, or the project is not registered.

Take those refusals at face value. A blocking decision means the captain owns the next move, not you.

### 2. Write the three inputs

The brief is the crewmate's entire world, and the split is the point:

- **`--intent`** — the captain's own ask, plus the context needed to read it. **Never** build instructions. A crewmate that does not know *why* cannot push back on *how*.
- **`--spec`** — how to build it. Optional; omit it when the intent and the definition of done are enough, and let the crewmate decide.
- **`--done`** — this feature's slice of the validation contract, in observable terms. Without it the crewmate decides for itself when it is finished.

Pass each as a file or on stdin with `-`.

### 3. Dispatch

```
./scripts/feature-dispatch.sh <mission> <feature> --intent i.md --spec s.md --done d.md
```

**`execution: crew`** — it does everything: renders the brief, creates the worktree, injects the hooks, resolves the allowlist, launches, and marks the feature `in_progress`. You are then free. Do not sit and poll; the watcher wakes you when the ledger moves.

**`execution: subagent`** — it prints the spawn spec and stops, because bash cannot call the Agent tool. Spawn the worker yourself with that spec, then set the feature `in_progress`.

### 4. When it finishes

`/crew` reads the outcome. Then:

| Outcome | Do |
|---|---|
| `done` | run the validators **against the live worktree** (`crew_meta_get <home> <task> worktree`), then tear down on green |
| `blocked` | file the decision (`/decide`), get an answer, `crew/send.sh` it. **Do not tear down** — blocked is waiting, not finished |
| `failed` | read the handoff. Re-brief, or `teardown.sh --abandon` deliberately |

A red validator verdict is a **re-brief, not a respawn**: append a `## Followup` to the same brief and steer the same crewmate on the same branch. It already has the context.

**Never tear down before validating.** Teardown removes the worktree the validator needs to read.

Full contract: [protocols/feature-loop.md](../../../protocols/feature-loop.md).
