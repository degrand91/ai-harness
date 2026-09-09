---
name: fleet
description: Show everything in flight across all registered projects — active missions, their features, open decisions, and spend. Read-only and cheap. Use to answer "where is everything?" at the start of a session or before deciding what to do next.
argument-hint: [--all]
allowed-tools: Bash(./scripts/fleet.sh *), Bash(./scripts/snapshot.sh *), Read
---

## The fleet

!`${CLAUDE_PROJECT_DIR}/scripts/fleet.sh $ARGUMENTS`

---

Summarise the above for the captain. Lead with whatever needs a decision, not with the inventory.

Order of attention:

1. **Unreadable missions** (`<- unreadable mission file`) — the tooling cannot classify these, so nothing else it says about them is trustworthy. Name them first.
2. **Open decisions** — a mission with `[N open decision(s)]` is blocked on the captain, not on work.
3. **Red or stalled features** — a feature that is `in_progress` with no recent activity.
4. **What is simply progressing** — one line, not a per-feature recital.

Then give one concrete "next action" sentence. It is your call, based on what the view shows:

- A mission with an open decision → present that decision, do not start new work.
- A feature `in_validation` with no verdict → spawn the scrutiny validator.
- All features closed, no post-mortem → `/mission-review`.
- Nothing in flight and undrained inbox notes → present the notes.

Read-only skill. Write nothing. `--all` includes closed and abandoned missions; without it, closed missions are hidden but unreadable ones are always shown.
