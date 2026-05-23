# Team

The harness operates with a fixed team of agent roles. Each role has a prompt in `agents/`, a protocol in `protocols/`, and is spawned via the Claude Code Agent tool with the right model and tools.

## Roster

| Role | Lifetime | Model (default) | Tools | Reads | Writes | Spawned by |
|------|----------|-----------------|-------|-------|--------|------------|
| **Orchestrator** | Mission-long | Opus | Full Claude Code | Everything in `missions/<id>/` + `learnings/` | `mission.md`, `plan.md`, `contract.md`, `status.json`, `log.md`, follow-up specs, `post-mortem.md` | User (you) |
| **Worker** | One feature | Sonnet | Full (Read/Write/Edit/Bash/Grep/Glob) | Feature spec + contract slice + previous handoff | Application code + one git commit + structured handoff | Orchestrator |
| **Scrutiny Validator** | One feature | Sonnet or Haiku | Read/Grep/Glob/Bash | Contract slice + diff | Verdict file (`scrutiny.md`) | Orchestrator |
| **User-Testing Validator** | One feature | Sonnet | Bash (launch app) + browser automation | User-facing contract slice + launch recipe | Verdict file (`user-test.md`) + evidence | Orchestrator |
| **Explorer** | One question | Haiku | Read/Grep/Glob/WebFetch | Whatever it can find | Returns findings; no FS writes | Orchestrator |
| **Sub-Orchestrator** *(rare)* | Subprogram | Opus | Full | Parent mission state | Subprogram state | Orchestrator |

## Why this team works

- **One Orchestrator** — single source of strategic intent. No coordination chaos.
- **Short-lived Workers** — fresh context per feature, no accumulated bias, codebase inheritance via git.
- **Adversarial Validators** — never see the Worker's frame; the contract is the only definition of done.
- **Cheap Explorers** — parallel reads during planning; killed before any feature spawns.
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
| Each role's prompt | `agents/<role>.md` |
| How a mission flows end-to-end | [protocols/lifecycle.md](protocols/lifecycle.md) |
| How handoffs work | [protocols/handoff.md](protocols/handoff.md) |
| Why one feature at a time | [protocols/serial-execution.md](protocols/serial-execution.md) |
| Which model goes where | [protocols/model-routing.md](protocols/model-routing.md) |
| A worked example | [examples/walkthrough.md](examples/walkthrough.md) |
