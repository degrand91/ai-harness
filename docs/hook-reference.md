# Hook Reference

This document describes every hook event the harness wires, the handler script for each, the stdin schema, the meaningful exit codes, and example input payloads.

Hook scripts live under `.claude/hooks/`. They are wired in `.claude/settings.json` under the `hooks` key.

---

## PostToolUse — `post-write-mission-state.sh`

**Trigger.** Fires after any `Write` or `Edit` tool call (matcher: `Write|Edit`).

**Purpose.** Appends a one-line entry to the active mission's `log.md` whenever a file inside `missions/<id>/` is written. Creates a lightweight audit trail of every state mutation without requiring the Orchestrator to log manually.

**Handler.** `.claude/hooks/post-write-mission-state.sh`

**Stdin schema.**

```json
{
  "tool_name": "Write",
  "tool_input": {
    "file_path": "/absolute/path/to/edited/file",
    "content": "..."
  }
}
```

The handler reads only `tool_input.file_path`. The `content` field is ignored.

**Exit codes.**

| Code | Meaning |
|------|---------|
| 0 | Always. Logging failures do not block the tool call. |

**Behaviour.** If the path does not contain `/harness/missions/`, the hook exits 0 immediately. If `log.md` does not exist yet, the hook also exits 0 (it does not create the file). It never logs mutations to `log.md` itself (infinite-loop guard).

**Example log line produced.**

```
[2026-05-23T14:31:02Z] [session=abc123] state mutation — features/001-init/spec.md edited
```

---

## PostToolUseFailure — `post-tool-use-failure.sh`

**Trigger.** Fires after any tool call that exits with an error (matcher fires on the `PostToolUseFailure` event, not `PostToolUse`).

**Purpose.** Logs a one-line failure entry to the active mission's `log.md`. Gives the Orchestrator an audit trail of tool errors without requiring manual logging. Exits 0 unconditionally so it never interferes with Claude Code's own error-handling path.

**Handler.** `.claude/hooks/post-tool-use-failure.sh`

**Stdin schema.**

```json
{
  "hook_event_name": "PostToolUseFailure",
  "tool_name": "Bash",
  "error": "exit status 1: command not found: jq"
}
```

All three fields are optional. The hook falls back to `"unknown"` for `tool_name` and `""` for `error` if absent.

**Exit codes.**

| Code | Meaning |
|------|---------|
| 0 | Always. Hook failure must never block Claude Code error handling. |

**Behaviour.** Resolves the harness root from `$CLAUDE_PROJECT_DIR`. If that variable is unset, the hook exits 0 immediately (no logging). Finds the most-recently-modified `missions/*/log.md` and appends one line. The error string is truncated to 200 characters to keep the log readable.

**Example log line produced.**

```
[2026-05-23T14:31:02Z] [session=abc123] tool-failure tool=Bash error=exit status 1: command not found: jq
```

If no mission log exists (e.g., before any mission has been started), the hook exits 0 silently.

---

## Stop — `stop-turnend-guard.sh`

**Trigger.** Fires when the Claude Code session attempts to end cleanly.

**Purpose.** Blocks session end if any active mission has a feature with `color: "red"` and no closed follow-up. Forces the Orchestrator to resolve open failures before leaving.

**Handler.** `.claude/hooks/stop-turnend-guard.sh`

**Stdin schema.** Claude Code passes context JSON; the hook discards it with `cat > /dev/null`.

**Exit codes.**

| Code | Meaning |
|------|---------|
| 0 | No red features; allow session to end. |
| 2 | Red feature(s) found; block session end. Error printed to stderr. |

**Example stderr on block.**

```
[Stop hook] Refusing to end — open red status detected:
  - Mission 2026-05-23-my-mission: red features without follow-ups: F003

Open a follow-up feature, or explicitly abandon/pause the mission by setting status.json.state.
```

**Skips missions in states:** `closed`, `abandoned`, `paused`, `awaiting_approval`, `intake`.

---

## SessionStart — `session-start-inject-status.sh`

**Trigger.** Fires once when a Claude Code session starts.

**Purpose.** Injects a summary of the most-recently-modified mission into the session context. Allows the Orchestrator to resume cleanly without manually running `/mission-status`.

**Handler.** `.claude/hooks/session-start-inject-status.sh`

**Stdin schema.** Claude Code passes a session-start payload; the hook discards it.

**Exit codes.**

| Code | Meaning |
|------|---------|
| 0 | Always. |

**Stdout schema (on active mission).**

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Active mission detected:\n  id: 2026-05-23-foo\n  state: executing\n  ..."
  }
}
```

If no active mission exists (most-recent mission is `closed` or `abandoned`, or `missions/` is empty), the hook outputs `{}`.

---

## SubagentStop — `subagent-stop-record.sh` and `subagent-stop-release-lock.sh`

Two hooks fire on the `SubagentStop` event. They run sequentially in the order listed in `settings.json`.

### `subagent-stop-record.sh`

**Purpose.** Appends a timing/type line to the most-recent active mission's `log.md`. Supports post-mortem cost analysis by agent role.

**Stdin schema.**

```json
{
  "hook_event_name": "SubagentStop",
  "agent_type": "worker"
}
```

The `agent_type` field may be absent on some Claude Code versions; the hook falls back to `"subagent"`.

**Exit codes.** Always 0.

**Example log line produced.**

```
[2026-05-23T14:35:11Z] subagent stopped — type=worker
```

### `subagent-stop-release-lock.sh`

**Purpose.** Releases the serial-spawn lock in `agent-spawn-state.json` when a subagent finishes. For non-explorer subagents, sets `in_flight_non_explorer` to `false`. For explorer subagents, decrements `explorer_count` (floor 0).

**Stdin schema.** Same as `subagent-stop-record.sh`.

**Exit codes.** Always 0. Lock release failures are non-blocking.

---

## PreToolUse — `pre-agent-spawn-serial.sh`

**Trigger.** Fires before any `Agent` tool call (matcher: `Agent`).

**Purpose.** Enforces the serial execution rule: only one non-explorer Worker/Validator may run at a time. Explorer subagents are always allowed concurrently.

**Handler.** `.claude/hooks/pre-agent-spawn-serial.sh`

**State file.** `.claude/hooks/agent-spawn-state.json`

```json
{
  "in_flight_non_explorer": false,
  "explorer_count": 0,
  "updated_at": "2026-05-23T14:00:00Z"
}
```

**Stdin schema.**

```json
{
  "tool_name": "Agent",
  "tool_input": {
    "subagent_type": "worker"
  }
}
```

**Exit codes.**

| Code | Meaning |
|------|---------|
| 0 | Allow spawn. |
| 2 | Block spawn (non-explorer already in flight). Error printed to stderr. |

**Stale-lock reset.** If `in_flight_non_explorer` is `true` but `updated_at` is more than 600 seconds in the past, the hook resets the lock and allows the spawn. This handles crashed Workers that never triggered `SubagentStop`.

---

## Notification — `notify-at-gate.sh`

**Trigger.** Fires on Claude Code `Notification` events (e.g., when the Orchestrator is waiting at the approval gate).

**Purpose.** Surfaces notifications to the operator via the best available delivery method: macOS Notification Center, Slack webhook, or email. Failure of any delivery method is silently ignored — notification failure must never block Claude Code.

**Handler.** `.claude/hooks/notify-at-gate.sh`

**Stdin schema.**

```json
{
  "hook_event_name": "Notification",
  "message": "Approval gate reached for mission 2026-05-23-foo. Review plan.md and contract.md.",
  "title": "Harness",
  "session_id": "abc123"
}
```

All fields are optional. The hook falls back to sensible defaults if absent.

**Exit codes.** Always 0.

**Configuration (environment variables).**

| Variable | Effect |
|----------|--------|
| `HARNESS_SLACK_WEBHOOK_URL` | POST notification to Slack incoming webhook. Requires `curl`. |
| `HARNESS_NOTIFY_EMAIL` | Send one-line email via `mail(1)`. Requires a configured MTA. |

If neither variable is set on a non-macOS host, the message is printed to stderr so it can be piped or redirected.
