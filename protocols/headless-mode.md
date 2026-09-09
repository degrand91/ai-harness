# Protocol: Headless Mode

> **Status: ASPIRATIONAL.**
>
> **Not implemented.** No script or hook drives a mission from cron or CI.
> Note that crewmates are already headless (`claude -p`) — that is unrelated to
> this document, which is about driving the *orchestrator* without a TTY.

Drive missions from cron jobs, CI pipelines, and shell scripts without an interactive TTY.

---

## Purpose

The harness normally runs inside an interactive Claude Code session where the Orchestrator reads user input and writes back in real time. Headless mode removes the human-in-the-loop from the execution path so that background and scheduled invocations can drive the same mission lifecycle — intake, plan, feature loop, close — autonomously.

Headless mode is appropriate for:
- **Cron jobs** — nightly or scheduled background runs.
- **CI/CD pipelines** — missions triggered on push, tag, or schedule.
- **Scripted orchestration** — chaining missions from a shell script or Makefile.
- **Non-interactive SSH sessions** — remote invocations where no terminal is attached.

---

## Invocation

```bash
claude --agent orchestrator -p "your goal here"
```

The `-p` flag supplies the initial user prompt non-interactively and causes Claude Code to exit when the session ends instead of waiting for further input.

### Minimal working example

```bash
CLAUDE_PROJECT_DIR=/path/to/harness \
  claude --agent orchestrator \
  -p "ship v0.9: add headless mode protocol and notification hook"
```

### Environment variables

| Variable | Required | Description |
|---|---|---|
| `CLAUDE_PROJECT_DIR` | Recommended | Absolute path to the harness root. Hooks and scripts use this to resolve relative paths. Defaults to the working directory if unset, but set it explicitly to avoid ambiguity in cron or CI environments. |
| `CLAUDE_SESSION_ID` | Optional | Pass a deterministic ID if you want to correlate logs across retries. When unset, Claude Code assigns one automatically. |
| `ANTHROPIC_API_KEY` | Required | Standard API key for the Anthropic API. Must be present in the environment before invocation. |
| `HARNESS_EXTERNAL_VALIDATOR_PROVIDER` | Optional | Set to a non-empty string (e.g. `openai`) to route scrutiny validation to an external provider via MCP. See `protocols/multi-provider-validation.md`. |

### Working directory

Claude Code resolves the project root from the working directory when `CLAUDE_PROJECT_DIR` is not set. In headless contexts this is often unpredictable. Always either:

1. Set `CLAUDE_PROJECT_DIR` explicitly, or
2. `cd` to the harness root before invoking.

```bash
cd /path/to/harness && claude --agent orchestrator -p "your goal"
```

---

## Output handling

In headless mode, Claude Code writes all session output to **stdout** and logs to **stderr**. The caller is responsible for capture and routing.

```bash
# Capture stdout; let stderr flow to the terminal (or a log file)
claude --agent orchestrator -p "..." > mission-output.txt 2>mission-errors.log
```

### Hook output

Hooks (`PostToolUse`, `Stop`, `SessionStart`, `SubagentStop`) run as child processes. Their stdout and stderr inherit the parent's file descriptors, so they appear interleaved with session output unless the caller redirects them separately.

The `stop-no-red-status.sh` hook exits non-zero if any mission is in a red state. In headless mode this causes `claude` to exit with a non-zero code, which CI pipelines can treat as a failure signal.

---

## Edge cases

### Missing TTY (color and prompts)

Without a TTY, Claude Code skips ANSI color codes automatically. No special flag is needed. If downstream log parsing breaks on control characters, pipe through `col -b` or set `NO_COLOR=1`.

### Hooks that write to the terminal

Some hooks use `osascript` (macOS Notification Center) or similar. These calls silently no-op when there is no graphical session. The hook should guard against this:

```bash
[[ "$TERM_PROGRAM" == "" ]] && exit 0   # headless, skip desktop notification
```

The `notify-at-gate.sh` hook (F002) includes this guard. See `protocols/remote-trigger.md` (F003) for the recommended pattern when headless runs need to surface human-attention events to a remote observer.

### Env var inheritance in cron

Cron strips most environment variables. Provide the full env explicitly in the crontab entry:

```cron
0 2 * * * ANTHROPIC_API_KEY=... CLAUDE_PROJECT_DIR=/path/to/harness \
  claude --agent orchestrator -p "nightly mission" >> /var/log/harness.log 2>&1
```

### Parallel invocations

The `pre-agent-spawn-serial.sh` hook holds a lock that prevents two Workers from running concurrently within a session. If two headless invocations start simultaneously against the same working directory, they share the same git working tree and may corrupt mission state. Use an external lock (e.g. `flock`) at the script level:

```bash
flock /tmp/harness.lock claude --agent orchestrator -p "..."
```

---

## Auto-approval

In headless mode there is no human watching the approval gate. The Orchestrator resolves this via the `feedback-blanket-approval` memory entry: when the prompt itself contains explicit pre-approval language (e.g. "do not stop", "continue through v1"), the Orchestrator treats the prompt as the approval artifact and advances past the gate autonomously.

If the prompt does not contain pre-approval language, the Orchestrator writes `contract.md` and `plan.md` as normal but cannot pause for human review. It will proceed and record in `log.md` that approval was auto-inferred from headless context. Use this only for fully trusted, scripted invocations.

---

## Notification

When a headless mission requires human attention — approval gate, validator failure requiring two follow-ups, hard blocker — the Orchestrator fires the **Notification hook** (wired in `settings.json` under `hooks.Notification`). The `notify-at-gate.sh` script delivers a desktop or remote notification so the operator knows to intervene.

See `protocols/remote-trigger.md` for how to surface these events to remote observers (webhooks, Slack, PagerDuty) when the operator is not at the machine running the job.

---

## Cross-references

- `feedback-blanket-approval` memory — `.claude/agent-memory/orchestrator/feedback_blanket_approval.md`
- Notification hook implementation — `.claude/hooks/notify-at-gate.sh` (F002)
- Remote trigger patterns — `protocols/remote-trigger.md` (F003, forward reference)
- Full mission lifecycle — `protocols/lifecycle.md`
- Model routing — `protocols/model-routing.md`
