---
name: ledger-first-over-process-state
description: A crewmate's own terminal report outranks whether its process is still running; deciding on process liveness alone blocks work that is demonstrably complete.
introduced_in_mission: 2026-09-09-fleet-shows-crew
tags: [crew, teardown, reconcile, liveness]
---

## Pattern

When a crewmate has written a terminal line (`done:` / `failed:`) to its
ledger, treat the work as finished — whatever its process is still doing. Check
process liveness only to distinguish *still working* from *vanished*, never to
decide whether finished work may be landed.

## Why

`claude -p` was observed lingering **14 minutes** after a crewmate had
committed its work and written `done:`. The rate-limit status was `allowed` and
utilization 0.01, so it was not throttled — it simply had not exited.

`reconcile.sh` was already ledger-first and reported the task as ready.
`teardown.sh` was process-first and refused for as long as the pid was alive,
so a hung CLI blocked a loop whose work was already committed. Two components
disagreed about the same question because only one of them had a rule.

The deeper point: **the ledger is the contract precisely because processes are
unreliable.** A design that says so and then quietly consults the process has
not adopted the principle, only described it.

## How to apply

- Read the outcome with `crew_outcome`, never from process state and never from
  the ledger's last line (lifecycle hooks append after the crewmate reports).
- Refuse on liveness only while the outcome is **not** terminal — that is the
  real case for "do not destroy a worktree being written to".
- When the outcome is terminal and the process lingers, stop it (TERM, then
  KILL after a grace period) and say so, rather than waiting for it.

## Origin

`missions/2026-09-09-fleet-shows-crew/post-mortem.md` — found by the first real
mission the harness ran, on itself.
