# Harness

A Factory.ai-Missions-inspired autonomous coding harness that runs on top of Claude Code.

**Goal.** You define **what**. The harness handles **how** — for hours, days, or weeks.

## What it is

A protocol, a registered team of subagents, a set of slash-skills, and a state convention. When you open a Claude Code session in this folder, the session **is** the Orchestrator (via `.claude/settings.json:agent`). Three roles:

- **Orchestrator** (this session) — plans features and milestones, writes the **validation contract** (what "done" means) *before any code is written*.
- **Workers** — short-lived subagents, fresh context per feature, implement and commit via git, hand off through structured reports.
- **Validators** — adversarial by design, never see the worker's reasoning. Two flavors: **scrutiny** (lint/typecheck/test/code-review) and **user-testing** (run the app, behave like QA).

Workers run **serially**. Parallelism is reserved for read-only work (codebase exploration via `explorer` subagents, doc reads, validation reviews).

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full model, [AGENTS.md](AGENTS.md) for the team roster, and [protocols/](protocols/) for each role's spec.

## Quickstart

```bash
# 1. From the harness folder, launch Claude Code as the Orchestrator.
#    The .claude/settings.json file sets `agent: orchestrator`, so this works:
claude

#    Equivalently, you can be explicit:
claude --agent orchestrator

# 2. In the session, start a mission with the bundled slash-skill:
/mission-start Add OAuth login to the demo app

#    Claude scopes through conversation, drafts the plan + validation contract,
#    waits for your approval — the only mandatory human gate.

# 3. Approve. The feature loop runs autonomously: worker → scrutiny → user-test → next.

# 4. Check progress any time (Claude-free, no tokens spent):
./scripts/status.sh                          # most recent mission
./scripts/status.sh 2026-05-23-add-oauth     # specific mission

# 5. Or, in-session:
/mission-status
/mission-list
/mission-resume 2026-05-23-add-oauth
```

The only shell script is `status.sh` — it lets you check mission state without spending tokens. Everything else (scaffolding, feature init, handoffs, validation) happens inline inside Claude's session via skills and the Write tool.

## What's inside

| Path | Purpose |
|------|---------|
| [CLAUDE.md](CLAUDE.md) | Operating manual every Claude session reads on entry |
| [ARCHITECTURE.md](ARCHITECTURE.md) | The five strategies, the three roles, state model |
| [AGENTS.md](AGENTS.md) | Team roster + agent communication graph |
| [ROADMAP.md](ROADMAP.md) | v0.1 → v1.0 journey and Beyond v1.0 forward planning |
| **`.claude/agents/`** | Registered subagents: orchestrator, worker, scrutiny-validator, user-testing-validator, explorer |
| **`.claude/skills/`** | Slash-skills: mission-start, mission-status, mission-resume, mission-review, mission-list, scaffold-feature, contract-check, log |
| **`.claude/hooks/`** | Procedure-enforcing hooks (PostToolUse log append, Stop block on red, SessionStart status inject, SubagentStop record) |
| **`.claude/settings.json`** | Session-level agent, permissions, hook wiring |
| `protocols/` | Reference specs for orchestrator, worker, validators, handoff, contract, lifecycle |
| `templates/` | Mission spec, validation contract, handoff report, post-mortem, status schema |
| `scripts/status.sh` | Claude-free status inspection |
| `missions/` | One folder per mission — all state lives here |
| `learnings/` | Curated cross-mission patterns + anti-patterns + proposals |
| `examples/` | Worked walkthrough and dry-run guide |

## Design principles

1. **Validation defines done, not the implementer.** The contract is written before the code and is the only source of truth.
2. **Serial features, parallel exploration.** Correctness compounds over multi-day runs.
3. **Fresh context per worker.** A worker inherits the codebase via git, not accumulated chat history.
4. **Adversarial validation.** Validators read the contract, not the worker's reasoning.
5. **Model-agnostic roles.** Each role can be routed to a different model (Opus for planning, Sonnet for code, Haiku for cheap exploration/validation).
6. **Use the platform.** Subagents, skills, hooks, and agent memory are all native Claude Code surfaces — the harness binds them together rather than reinventing them.
7. **The harness improves itself.** Every mission ends with a post-mortem; patterns get distilled into `learnings/` and into the orchestrator's `.claude/agent-memory/`.

## Contributing and License

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a PR —
in particular the dog-food rule (harness changes go through a mission) and the contract
discipline requirements.

This project is released under the [MIT License](LICENSE).

Community standards are governed by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

To report a security vulnerability, see [SECURITY.md](SECURITY.md).

## Credits

Built on insights from ECC ([affaan-m/ECC](https://github.com/affaan-m/ECC), MIT). See [docs/credits.md](docs/credits.md).

## Status

**v1.0** — shipped 2026-05-23. Full Claude Code integration: subagents, skills, hooks, settings, multi-provider model routing, learning loop, parallel exploration, mission control (status/resume/list), resumability, and production infrastructure. See [ROADMAP.md](ROADMAP.md) for the v0.1 → v1.0 journey and the Beyond v1.0 forward planning section.
