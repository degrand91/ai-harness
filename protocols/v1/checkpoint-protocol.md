# Protocol: Checkpoint Emission

Checkpoints allow a new Claude session to resume an in-flight mission without losing context. This protocol defines what a checkpoint contains, when to emit one, how to read it back, and how it relates to the other mission-state files.

---

## What is a checkpoint?

A checkpoint is a JSON snapshot written to `missions/<id>/checkpoint.json`. It captures the mission's position in the feature loop at a given moment in time: which features are done, which are still pending, which is active, and what the next concrete action is.

A checkpoint does **not** replace `status.json` or `log.md`. Those remain the authoritative source of truth. The checkpoint is a derived summary optimised for fast session-start reads.

---

## Schema: `missions/<id>/checkpoint.json`

```json
{
  "mission_id": "<id>",
  "session_id": "<CLAUDE_SESSION_ID or unknown>",
  "checkpoint_at": "<ISO 8601 timestamp>",
  "mission_state": "<state from status.json>",
  "completed_features": ["F001", "F002"],
  "remaining_features": ["F003", "F004"],
  "current_feature": "<F00X or null>",
  "last_commit_sha": "<short SHA from git log -1>",
  "post_mortem_present": false,
  "next_action": "spawn worker for F003 | run integration check | author post-mortem | mission already closed"
}
```

### Field descriptions

| Field | Type | Description |
|---|---|---|
| `mission_id` | string | The mission folder name, e.g. `2026-05-23-add-oauth`. |
| `session_id` | string | `$CLAUDE_SESSION_ID` at emit time, or `"unknown"` if unavailable. |
| `checkpoint_at` | string | ISO 8601 timestamp of when the checkpoint was written. |
| `mission_state` | string | Value of `.state` from `status.json` at snapshot time. |
| `completed_features` | array | Feature IDs whose state is `closed`. |
| `remaining_features` | array | Feature IDs whose state is `pending` or `in_progress`. |
| `current_feature` | string or null | The feature currently `in_progress`, or `null` if none. |
| `last_commit_sha` | string | Short SHA from `git log -1 --pretty=%h` at emit time. |
| `post_mortem_present` | boolean | Whether `missions/<id>/post-mortem.md` exists. |
| `next_action` | string | Human-readable instruction for what the orchestrator does next. |

---

## When to emit a checkpoint

Emit a checkpoint in the following three situations:

### 1. After every feature close

When the orchestrator transitions a feature's state to `closed` (i.e., the scrutiny validator returns green and the feature handoff is recorded), emit a checkpoint immediately before moving to the next feature.

This ensures that if the session ends between features, the next session knows exactly which feature to spawn the Worker for.

### 2. At orchestrator session-end

Before the orchestrator's session terminates — whether by completing the mission, reaching a stopping point, or being interrupted — emit a final checkpoint. The `Stop` hook may trigger this automatically, but the orchestrator should also call it explicitly when transitioning to `closing` state.

This is the primary recovery point for session-boundary resume.

### 3. Every N=5 features (long missions)

For missions with more than ten features, emit an additional checkpoint after every fifth completed feature, even if the session is still active. This limits the window of lost context if a session dies unexpectedly mid-feature.

---

## How to emit

Run the script directly:

```bash
./scripts/mission-checkpoint.sh <mission-id>
```

The script reads `missions/<id>/status.json`, computes the checkpoint fields, writes `checkpoint.json`, and echoes the JSON to stdout.

The orchestrator may also invoke the script via a Bash tool call. No arguments other than the mission-id are required.

---

## How a fresh session picks it up

The `/mission-resume` skill (`.claude/skills/mission-resume/SKILL.md`) reads `checkpoint.json` first, then reconciles against `status.json` to confirm state is consistent. The procedure is:

1. Read `checkpoint.json` — use it as the quick-start summary.
2. Read `status.json` — verify `mission_state` and `current_feature` match.
3. If they disagree, trust `status.json` and discard the stale checkpoint.
4. Read `MEMORY.md` for chain context.
5. Print the structured resume briefing and proceed with `next_action`.

The `SessionStart` hook (`session-start-inject-status.sh`) also injects active-mission context at session start, so checkpoint content may already be partially surfaced before `/mission-resume` is invoked.

---

## Relationship to other state files

| File | Role | Updated by |
|---|---|---|
| `status.json` | Authoritative current state; machine-readable | Orchestrator (writes) |
| `log.md` | Append-only event timeline | `PostToolUse` hook (auto) + orchestrator |
| `checkpoint.json` | Derived snapshot for session-start resume | `scripts/mission-checkpoint.sh` |
| `MEMORY.md` | Orchestrator's personal scratchpad across sessions | Orchestrator (writes) |

Never edit `checkpoint.json` by hand. Always regenerate it via the script.

---

## Cross-references

- [protocols/lifecycle.md](lifecycle.md) — state machine that drives when checkpoints are emitted.
- [.claude/skills/mission-resume/SKILL.md](../.claude/skills/mission-resume/SKILL.md) — how the next session reads the checkpoint.
- `scripts/mission-checkpoint.sh` — the script that writes `checkpoint.json`.
