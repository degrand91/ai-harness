# Command: mission-resume

> Invoke when picking up a mission across sessions, or after a pause.

## What it does

Restores Orchestrator context from filesystem state and continues from the last recorded transition.

## Procedure

1. Identify the mission id (user-specified or most recent under `missions/`).
2. Read in this order:
   1. `mission.md` — user intent.
   2. `plan.md` — feature plan.
   3. `contract.md` — definition of done.
   4. `status.json` — current state.
   5. `log.md` — last 20 entries.
   6. The current feature's `spec.md`, `handoff.md`, `scrutiny.md`, `user-test.md` if they exist.
3. Reconcile state:
   - If `status.json` says `state: "paused"`, transition to `executing` and log it.
   - If `status.json` says `state: "executing"` and a worker handoff exists without a verdict, the next action is to spawn the Validator.
   - If a feature is green and there's a next feature pending, the next action is to spawn its Worker.
   - If unsure, run the contract slice for the last green feature to confirm the repo state matches the log.
4. Surface a short "resuming from X" message to the user, then continue.

## Trust the files, not memory

Across sessions, the Orchestrator has no memory. The filesystem is the canonical state. If `log.md` and your inferred state disagree, the file wins.

## Anti-patterns

- ❌ Re-running completed features.
- ❌ Skipping the contract slice replay when you can't tell from the log whether the worker actually finished.
- ❌ Discarding follow-ups because they "look stale."
