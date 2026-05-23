# Team

The harness operates with a fixed team of agent roles. Each role is a real Claude Code subagent at `.claude/agents/<name>.md` (YAML frontmatter + system prompt). Each is spawned via the Agent tool with the matching `subagent_type`.

## Roster

| Role | `subagent_type` | Lifetime | Default model | Tools | Memory |
|------|-----------------|----------|---------------|-------|--------|
| **Orchestrator** | (session-level via `.claude/settings.json:agent`) | Mission-long | Opus | Full Claude Code | `project` — `.claude/agent-memory/orchestrator/` |
| **Worker** | `worker` | One feature | Sonnet | Read, Write, Edit, Bash, Grep, Glob | none (fresh per spawn) |
| **Scrutiny Validator** | `scrutiny-validator` | One feature | Haiku | Read, Grep, Glob, Bash (no Write/Edit) | none (adversarial) |
| **User-Testing Validator** | `user-testing-validator` | One feature | Sonnet | Bash, Read, Grep, Glob (no Write/Edit) | none |
| **Explorer** | `explorer` | One question | Haiku | Read, Grep, Glob, WebFetch, WebSearch (no Bash, no Write/Edit) | none |

## How to spawn one

You **never inline a role prompt**. The system prompt is loaded from `.claude/agents/<name>.md` automatically.

```text
Agent(
  subagent_type: "worker",
  model: "sonnet",
  description: "Worker — F003 add-oauth-routes",
  prompt: <feature spec> + <contract slice> + <previous handoff if any>
)
```

## Why this team works

- **One Orchestrator** — single source of strategic intent. The `agent: orchestrator` setting makes the main session take on the role automatically.
- **Short-lived Workers** — fresh context per feature, no accumulated bias, codebase inheritance via git.
- **Adversarial Validators** — never see the Worker's frame; the contract is the only definition of done. Tool denylist enforces no-edit at the Claude Code permission layer.
- **Cheap Explorers** — parallel reads during planning; killed before any feature spawns. Bash disabled, so they can't shell out.
- **No peer-to-peer chat** — all coordination is through filesystem state (the Broadcast pattern from the Missions taxonomy).

## How agents communicate (and don't)

```
                     ┌────────────────────────────┐
                     │       ORCHESTRATOR         │
                     │  (this Claude session)     │
                     └────┬───────────┬───────────┘
                          │           │
              ┌───────────┘           └───────────┐
              ▼                                   ▼
      ┌───────────────┐                  ┌──────────────────┐
      │    WORKER     │  ────commit────▶ │      git HEAD    │
      │ (fresh ctx)   │                  │   (next worker   │
      └───────┬───────┘                  │   reads via git) │
              │                          └─────────┬────────┘
              ▼                                    │
       handoff.md                                  │
              │                                    │
              ▼                                    │
      ┌───────────────┐         contract+diff      │
      │  SCRUTINY V.  │  ◀──────(no handoff)──────┘
      │ (fresh ctx,   │
      │ adversarial)  │
      └───────┬───────┘
              ▼
        scrutiny.md
              │
              ▼ (in parallel)
      ┌───────────────────┐
      │ USER-TESTING V.   │  ──── runs the app ────▶ evidence/*
      │ (fresh ctx, QA)   │
      └───────┬───────────┘
              ▼
        user-test.md

   broadcast channel (all roles read, only Orchestrator writes):
        log.md  +  status.json  +  contract.md
```

**Forbidden communication paths** (per the Missions design):
- Worker ↔ Validator direct chat
- Worker N ↔ Worker N-1 direct chat (Worker reads previous handoff, but does not converse)
- Validator ↔ Validator chat
- Anything peer-to-peer

## Where to read more

| To learn… | Read |
|-----------|------|
| The day-one operating manual | [CLAUDE.md](CLAUDE.md) |
| The design model | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Each role's spec | `protocols/<role>.md` |
| Each role's actual prompt | `.claude/agents/<role>.md` |
| Each slash-skill | `.claude/skills/<name>/SKILL.md` |
| How a mission flows end-to-end | [protocols/lifecycle.md](protocols/lifecycle.md) |
| How handoffs work | [protocols/handoff.md](protocols/handoff.md) |
| Why one feature at a time | [protocols/serial-execution.md](protocols/serial-execution.md) |
| Which model goes where | [protocols/model-routing.md](protocols/model-routing.md) |
| A worked example | [examples/walkthrough.md](examples/walkthrough.md) |
