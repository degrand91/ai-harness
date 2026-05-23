# .claude/

Native Claude Code integration for the harness. Everything in here is a real Claude Code surface — picked up automatically when a session is opened at the harness root.

## Layout

```
.claude/
├── settings.json          # session-level agent, permissions, hook wiring
├── agents/                # registered subagents (spawn via Agent tool by name)
│   ├── orchestrator.md       — main-session role (set via settings.json:agent)
│   ├── worker.md             — implements one feature, returns structured handoff
│   ├── scrutiny-validator.md — adversarial code review against contract
│   ├── user-testing-validator.md — QA against the running app
│   └── explorer.md           — read-only recon (the only role allowed to fan out)
├── skills/                # invokable as /<skill-name>
│   ├── mission-start/
│   ├── mission-status/
│   ├── mission-resume/
│   ├── mission-review/
│   ├── mission-list/
│   ├── scaffold-feature/
│   ├── contract-check/
│   └── log/
├── hooks/                 # lifecycle enforcement
│   ├── post-write-mission-state.sh   — auto-append mission log on edits
│   ├── stop-no-red-status.sh         — block session end if any mission is red
│   ├── session-start-inject-status.sh — surface active mission on session open
│   └── subagent-stop-record.sh       — record subagent finish events
└── agent-memory/          # auto-created by Claude Code as orchestrator builds memory
    └── orchestrator/MEMORY.md
```

## What auto-loads

- `agents/*.md` — discovered on session start. Spawn with `Agent({ subagent_type: "<name>", ... })`. No need to inline the system prompt.
- `skills/<name>/SKILL.md` — discovered on session start. Invoke with `/<name>` (and live in the `/` menu if `user-invocable` isn't false).
- `settings.json` — read on session start. `agent: orchestrator` makes the main session run with the orchestrator system prompt. Permissions and hooks apply automatically.
- `hooks/*.sh` — invoked by Claude Code at the event matched in `settings.json`. Must be executable.

## Settings highlights

- `"agent": "orchestrator"` — the main session **is** the Orchestrator.
- `"includeCoAuthoredBy": false` — respects the user's global no-attribution rule.
- `"permissions.defaultMode": "acceptEdits"` — Auto Mode for fast iteration. Spawned Workers inherit this.
- `"permissions.allow"` — pre-approves mission-state edits, status.sh, common git read commands, and Agent/Skill invocation by name.
- `"permissions.deny"` — blocks `rm -rf /`, `git push --force`, edits to `contract.md` from anywhere (so the contract can only be amended via the templated amendments log), and `.env` reads.
- `"permissions.ask"` — pauses on `git push`, `git reset --hard`, `git rebase`.

## Memory

Only the Orchestrator has `memory: project`. Workers and Validators are deliberately fresh-per-spawn — that's how adversarial verification works. The Orchestrator's memory lives at `.claude/agent-memory/orchestrator/MEMORY.md` and is committed alongside the rest of the harness (project-scoped, shareable).

## Hook semantics

| Hook | Event | What it does | Block? |
|------|-------|--------------|--------|
| `post-write-mission-state.sh` | `PostToolUse:Write\|Edit` | Appends `[ts] state mutation — <path>` to the active mission's `log.md` if the edited file is under `missions/<id>/`. Idempotent enough. | No |
| `stop-no-red-status.sh` | `Stop` | Refuses to end the session if any mission has red features without follow-ups. Exit 2 + stderr message. | **Yes** |
| `session-start-inject-status.sh` | `SessionStart` | Injects the active mission's status into context (mission id, state, current feature, last 5 log lines). | No |
| `subagent-stop-record.sh` | `SubagentStop` | Logs subagent type + timestamp to the active mission's log. Feeds the post-mortem cost aggregation. | No |

## How to extend

- Add a new subagent → drop a Markdown file in `agents/` with YAML frontmatter (`name`, `description`, `tools`, `model`, …). Reload the session.
- Add a new slash-skill → `mkdir skills/<name>` then write `SKILL.md`. Live-reloads (Claude Code watches the directory).
- Add a new hook → write the script in `hooks/`, mark it executable, register it in `settings.json:hooks.<Event>`.

Refer to the canonical docs at <https://code.claude.com/docs/en/sub-agents>, <https://code.claude.com/docs/en/skills>, <https://code.claude.com/docs/en/hooks>, <https://code.claude.com/docs/en/settings>.
