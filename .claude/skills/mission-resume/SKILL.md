---
name: mission-resume
description: Pick up an in-flight mission across sessions. Reads mission.md, plan.md, contract.md, status.json, and the last 20 log entries to restore Orchestrator context. Use this at the start of any session where you intend to continue an existing mission.
argument-hint: [mission-id]
allowed-tools: Read, Bash(ls *), Bash(cat *), Bash(/Users/stefanodegrandis/projects/ai/harness/scripts/status.sh *), Grep, Glob
---

## Available missions
!`ls -1 ${CLAUDE_PROJECT_DIR}/missions 2>/dev/null | grep -v '^\\.gitkeep$' || echo "(none)"`

## Argument
Mission id (or empty = most recent): $ARGUMENTS

---

Resume a mission. Do not infer state from memory — read the files. The filesystem is the source of truth.

## Procedure

1. **Determine mission id.** If `$ARGUMENTS` is empty, pick the most recently modified folder under `missions/`. Otherwise use the argument.

2. **Read in this exact order**, with the Read tool:
   1. `missions/<id>/mission.md` — user intent.
   2. `missions/<id>/plan.md` — feature plan.
   3. `missions/<id>/contract.md` — definition of done.
   4. `missions/<id>/status.json` — current state.
   5. Last 20 entries of `missions/<id>/log.md`.
   6. The **current feature's** `spec.md`, `handoff.md`, `scrutiny.md`, `user-test.md` if they exist.

3. **Reconcile state:**
   - If `status.json.state == "paused"` → transition to `executing`, append a log line.
   - If `status.json.state == "executing"` and a worker handoff exists without a verdict → next action is to spawn the Scrutiny Validator.
   - If a feature is `closed` and there's a next feature pending → next action is to spawn its Worker.
   - If unsure → re-run the contract slice for the last green feature to confirm the repo state matches the log. The Bash `/contract-check` skill helps here.

4. **Surface a "resuming from X" message** to the user, then proceed with the next action.

## Hard rules

- Trust the files, not your inferred state. If `log.md` and what you think are happening disagree, the file wins.
- Do not re-run completed features.
- Do not discard follow-ups because they "look stale."
- Do not edit `mission.md`, `plan.md`, or `contract.md` on resume — those are immutable artifacts of the original session. Amendments go in the contract's "Amendments log" section, with timestamp and reason.
