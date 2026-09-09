---
name: resume
description: Hand the wheel back to the harness on a paused mission and let the loop continue. Use when the captain says carry on, resume, or go ahead after a pause.
argument-hint: [mission-id]
allowed-tools: Bash(./scripts/status.sh *), Bash(./scripts/fleet.sh), Bash(./scripts/hold.sh *), Read, Edit
---

Set the mission's `state` back to `executing` in `missions/<id>/status.json`, then say what happens next in one line — the next feature to dispatch, or the validator to run.

Before resuming, check two things:

1. **Are there open decisions on this mission?** If a blocking one is unanswered, resuming will simply stop again at the same place. Present it first (`/decide`).
2. **Did anything change while paused?** If the captain edited files by hand, the in-flight brief may be stale — say so rather than dispatching against it.

If no mission id is given and exactly one is paused, resume that one.
