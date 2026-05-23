# Harness

A Factory.ai-Missions-inspired autonomous coding harness that runs on top of Claude Code.

**Goal.** You define **what**. The harness handles **how** — for hours, days, or weeks.

## What it is

A protocol, a set of role prompts, and a state convention. When Claude Code is invoked inside this folder with a mission, it adopts a three-role workflow:

- **Orchestrator** — plans features and milestones, writes the **validation contract** (what "done" means) *before any code is written*.
- **Workers** — fresh context per feature, implement and commit via git, hand off through structured reports.
- **Validators** — adversarial by design, never saw the worker's code. Two flavors: **scrutiny** (lint/typecheck/test/code-review) and **user-testing** (run the app, behave like QA).

Workers run **serially**. Parallelism is reserved for read-only work (codebase exploration, doc reads, validation reviews).

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full model and [protocols/](protocols/) for each role's spec.

## Quickstart

```text
# 1. Open a Claude Code session at this folder. Tell Claude:
#       Start a mission: "Add OAuth login to the app"
#
#    Claude scaffolds missions/<id>/ inline (no shell scripts),
#    scopes through conversation, drafts the plan + validation contract,
#    and waits for your approval — the only mandatory human gate.

# 2. Approve when you're happy with the plan + contract.
#    Claude then executes the feature loop autonomously.

# 3. Check progress any time (Claude-free, no tokens spent):
./scripts/status.sh                          # most recent mission
./scripts/status.sh 2026-05-23-add-oauth     # specific mission
```

The only shell script is `status.sh` — it lets you check mission state without spending tokens. Everything else (scaffolding, feature init, handoffs, validation) happens inline inside Claude's session, where it belongs.

## What's inside

| Path | Purpose |
|------|---------|
| [CLAUDE.md](CLAUDE.md) | Operating manual every Claude session reads on entry |
| [ARCHITECTURE.md](ARCHITECTURE.md) | The five strategies, the three roles, state model |
| [ROADMAP.md](ROADMAP.md) | Phased iteration plan, v0.1 → v1.0 |
| `protocols/` | Specs for orchestrator, worker, validators, handoff, contract |
| `agents/` | Role prompts injected into spawned subagents |
| `templates/` | Mission spec, validation contract, handoff report, post-mortem |
| `commands/` | Slash-command-style entry points (mission-start, mission-status, etc.) |
| `scripts/` | Shell helpers (init, record-handoff, validate) |
| `missions/` | One folder per mission — all state lives here |
| `learnings/` | Distilled patterns from past missions, fed back into the orchestrator |
| `hooks/` | Optional Claude Code hooks that enforce procedure |
| `examples/` | Worked example missions |

## Design principles

1. **Validation defines done, not the implementer.** The contract is written before the code and is the only source of truth.
2. **Serial features, parallel exploration.** Correctness compounds over multi-day runs.
3. **Fresh context per worker.** A worker inherits the codebase via git, not accumulated chat history.
4. **Adversarial validation.** Validators read the contract, not the worker's reasoning.
5. **Model-agnostic roles.** Each role can be routed to a different model (Opus for planning, Sonnet for code, Haiku for cheap exploration, a different provider for validation when feasible).
6. **The harness improves itself.** Every mission ends with a post-mortem; patterns get distilled into `learnings/` and injected into future orchestrator prompts.

## Status

**v0.1** — protocols, templates, slash commands, manual orchestration by Claude. Iteration plan in [ROADMAP.md](ROADMAP.md).
