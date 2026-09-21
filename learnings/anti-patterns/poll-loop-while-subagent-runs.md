---
name: poll-loop-while-subagent-runs
description: The orchestrator parks in a `sleep 30` loop while a worker runs; every wake is a full model turn over the whole context (~50 per feature), and the stops drown the mission log. Subagents run in the background — end the turn and let the completion notification wake you.
introduced_in_mission: 2026-09-21-harness-throughput-review
tags: [orchestrator, subagent, cost, latency, log]
---

## Anti-pattern

After spawning a worker or validator, the orchestrator waits for it with a bounded
`until … sleep 30` Bash loop (or re-arms one after a timeout). Each iteration
returns control to the model: a full turn, reading a 100k+ token context, to
learn that nothing has happened. A 25-minute worker produces ~50 such turns.

Observed across every mission from 2026-09-18 to 2026-09-21: 156/212 and
290/353 log lines were `subagent stopped` at a 32-second cadence, and 29
orphaned wait shells were found on 2026-09-19.

## Why it's tempting

The orchestrator wants to "stay in control" and the in-process subagent used to
block the tool call, so a loop felt like the only way to remain responsive.
That premise is gone: Claude Code runs subagents in the background and delivers
a completion notification.

## What to do instead

1. Spawn. Set the feature `in_progress` in `status.json`. **End the turn.**
2. The `SubagentStop` hook persists the handoff/verdict and releases the serial
   lock; the completion notification wakes the orchestrator.
3. The turn-end guard treats a held, recent spawn lock as work in flight, so
   stopping is never mistaken for a blind stop.
4. If something genuinely needs a timer (a CI run, a release build), use one
   bounded background task with a marker and stop it when the answer arrives
   by any other route — never a loop per subagent.
