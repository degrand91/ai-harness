---
name: mission-resume
description: Pick up an in-flight mission across sessions. Reads checkpoint.json (fast-start summary), status.json (authoritative state), and MEMORY.md (chain context) to produce a structured resume briefing the Orchestrator can act on immediately. Use this at the start of any session where you intend to continue an existing mission.
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
   1. `missions/<id>/checkpoint.json` — fast-start summary (if present). Use this as the primary source of "what's left". If absent, continue; the remaining reads will reconstruct state.
   2. `missions/<id>/status.json` — authoritative current state. Always read this. If `checkpoint.json` was present, verify that `mission_state` and `current_feature` match. If they disagree, trust `status.json` and treat the checkpoint as stale.
   3. `.claude/agent-memory/orchestrator/MEMORY.md` — chain context from the previous session. Read this to recover any orchestrator-level notes that are not reflected in the mission files.
   4. `missions/<id>/mission.md` — user intent (read only if the above three do not already make the goal clear, or always for correctness).
   5. `missions/<id>/plan.md` — feature plan.
   6. `missions/<id>/contract.md` — definition of done.
   7. Last 20 entries of `missions/<id>/log.md`.
   8. The **current feature's** `spec.md`, `handoff.md`, `scrutiny.md`, `user-test.md` if they exist.

3. **Output the structured resume briefing** (print every section; leave a field blank only if genuinely unavailable):

   ```
   ## Resume Briefing — <mission-id>

   ### Mission identity
   - Goal: <one-line summary from mission.md>
   - Contract: <path to contract.md>

   ### Current state
   - Mission state: <status.json .state>
   - Current feature: <current_feature from checkpoint.json / status.json, or "none">
   - Checkpoint timestamp: <checkpoint.json .checkpoint_at, or "no checkpoint">

   ### Last commit
   - SHA: <checkpoint.json .last_commit_sha, or output of git log -1 --pretty=%h>

   ### Pending features
   - Remaining: <checkpoint.json .remaining_features list, or derived from status.json>
   - Completed: <checkpoint.json .completed_features list, or derived from status.json>

   ### Recommended next action
   <checkpoint.json .next_action verbatim if present; otherwise derived from reconciled state — see Reconcile state below>

   ### Chain context
   <Relevant notes from MEMORY.md — orchestrator scratchpad from the previous session.
    Summarise any in-flight decisions, open questions, or risk flags recorded there.
    If MEMORY.md is empty or absent, write "None recorded.">
   ```

4. **Reconcile state** (if `checkpoint.json` was absent or stale):
   - If `status.json.state == "paused"` → transition to `executing`, append a log line.
   - If `status.json.state == "executing"` and a worker handoff exists without a scrutiny verdict → next action is to spawn the Scrutiny Validator.
   - If a feature is `closed` and there's a next feature pending → next action is to spawn its Worker.
   - If unsure → re-run the contract slice for the last green feature to confirm the repo state matches the log. The `/contract-check` skill helps here.

5. **Proceed** with the recommended next action immediately after printing the briefing. Do not wait for the user to confirm unless something is genuinely ambiguous.

## Hard rules

- Trust the files, not your inferred state. If `log.md` and what you think are happening disagree, the file wins.
- `checkpoint.json` is a derived snapshot — it is a convenience, not the authority. Always cross-check against `status.json`.
- Do not re-run completed features.
- Do not discard follow-ups because they "look stale."
- Do not edit `mission.md`, `plan.md`, or `contract.md` on resume — those are immutable artifacts of the original session. Amendments go in the contract's "Amendments log" section, with timestamp and reason.
