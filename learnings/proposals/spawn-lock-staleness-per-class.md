---
name: spawn-lock-staleness-per-class
description: The serial-spawn lock's stale reset keys off one shared updated_at, so any unrelated write (e.g. a stop event for another agent type) refreshes it and a leaked validator slot never expires; validators that stop on maxTurns appear not to release their slot.
introduced_in_mission: private
tags: [harness, hooks, serial-spawn, locks]
---

## Problem

A worker spawn was refused with "1 validator(s) still reading the tree" although no validator was running. `validator_count` was 1, left over from two validators that hit `maxTurns` (no clean release). The 600 s stale reset in `pre-agent-spawn-serial.sh` never fired, because a `SubagentStop` for an agent of type `orchestrator` at 21:37:20Z rewrote the state file and refreshed `updated_at`. The orchestrator repaired the state by hand after confirming every spawned agent had reported.

## Proposal

- Track `validator_since` and `worker_since` separately, updated only when that class's count changes; apply the stale reset per class.
- In `subagent-stop-release-lock.sh`, treat an unknown or non-harness `agent_type` as a no-op (do not rewrite the file).
- Add a test: validator spawned, no release, an unrelated stop event at +5 min, worker spawn at +11 min → allowed.
