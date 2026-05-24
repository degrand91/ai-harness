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
| **Scout** | `scout` | Cross-mission (long-lived) | Haiku | Read, Grep, Glob, WebFetch, WebSearch | `project` — `.claude/agent-memory/scout/` |
| **Scrutiny Validator (external)** | `scrutiny-validator-external` | One feature (env-gated) | Haiku (via MCP to external provider) | Read, Grep, Glob, Bash (no Write/Edit) | none |

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

   Note: Scout sits off to the side, consulted at intake by the Orchestrator
   for cross-mission memory before planning begins. It is never fanned out.
```

**Forbidden communication paths** (per the Missions design):
- Worker ↔ Validator direct chat
- Worker N ↔ Worker N-1 direct chat (Worker reads previous handoff, but does not converse)
- Validator ↔ Validator chat
- Anything peer-to-peer

## ECC-Ported Standalone Agents

These agents are **not** part of the core mission loop. They are standalone assistants ported from ECC (MIT) that the Orchestrator or user can spawn for specific tasks at any time. They do not produce handoffs or feed into the validation pipeline.

| Agent | `subagent_type` | Default model | Tools | Purpose |
|-------|-----------------|---------------|-------|---------|
| **architect** | `architect` | opus | Read, Grep, Glob | Architectural analysis and system design decisions |
| **code-reviewer** | `code-reviewer` | sonnet | Read, Grep, Glob, Bash | Code quality review, patterns, and best practices |
| **doc-updater** | `doc-updater` | haiku | Read, Write, Edit, Bash, Grep, Glob | Documentation maintenance and updates |
| **harness-optimizer** | `harness-optimizer` | sonnet | Read, Grep, Glob, Bash, Edit | Harness performance and configuration improvements |
| **refactor-cleaner** | `refactor-cleaner` | sonnet | Read, Write, Edit, Bash, Grep, Glob | Dead code removal and structural refactoring |
| **security-reviewer** | `security-reviewer` | sonnet | Read, Write, Edit, Bash, Grep, Glob | Security vulnerability analysis (OWASP, secrets, auth) |
| **silent-failure-hunter** | `silent-failure-hunter` | sonnet | Read, Grep, Glob, Bash | Detects swallowed errors and non-surfaced failures |
| **tdd-guide** | `tdd-guide` | sonnet | Read, Write, Edit, Bash, Grep | Test-driven development guidance and enforcement |

Their prompts live in `.claude/agents/`. Spawn them via the Agent tool with the matching `subagent_type`.

---

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
