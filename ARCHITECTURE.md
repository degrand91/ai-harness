# Architecture

> Sections 2, 5 and 9 were revised when the crew execution model landed. If this
> document and [protocols/](protocols/) ever disagree, the protocols win: they
> sit next to the code and are what the orchestrator actually loads.


The harness is a thin protocol layer on top of Claude Code that adopts the Factory.ai Missions model: **one Orchestrator, many short-lived Workers, adversarial Validators**, glued together by a **validation contract** written before any code is.

This document is the design reference. For how to *operate* it, see [CLAUDE.md](CLAUDE.md).

---

## 1. The five multi-agent strategies

| # | Strategy | Description |
|---|----------|-------------|
| 1 | **Delegation** | One agent spawns another for a subtask. The simplest pattern. |
| 2 | **Creator-Verifier** | One agent builds, a different agent checks. Separation of concerns removes sunk-cost bias. |
| 3 | **Direct Communication** | Agents talk peer-to-peer without a coordinator. Hard to get right — state fragments. |
| 4 | **Negotiation** | Two agents coordinate over shared resources. Best when there's a possible win-win. |
| 5 | **Broadcast** | One agent sends status updates and shared context to many. Critical for coherence. |

The harness composes **#1, #2, #4, #5**. It deliberately omits #3.

---

## 2. The three roles

### Orchestrator (you, the main Claude session)

Plans features and milestones, writes the validation contract before any code
exists, dispatches work, decides, and lands finished work. **It never edits
application files.**

### Workers — one of two execution models

A mission records `execution` in `status.json`, decided once at intake and never
changed afterwards. [protocols/feature-loop.md](protocols/feature-loop.md) owns
the decision; `scripts/feature-dispatch.sh` implements it.

| | `crew` | `subagent` |
|---|---|---|
| The worker is | a headless `claude -p` process in its own git worktree | a short-lived in-process `Agent` call |
| The orchestrator, meanwhile | **free** — it can answer you and watch other projects | **blocked** inside the tool call for the whole duration |
| Requires | the `target_repo` to be a registered project | nothing |
| Survives a session death | yes: worktree and ledger reconcile from disk | no |
| Reports through | an append-only ledger it writes itself | the Agent tool's return value |

**Registration decides the default.** Registering a project
(`scripts/project.sh add`) is the operator's explicit act and carries the
delivery posture the crew needs, so a registered `target_repo` means `crew`.

The `crew` model is what makes this a control plane rather than a tool that runs
one thing at a time: with in-process subagents the controller is blocked for the
entire duration of any work it dispatches, and a controller that cannot answer
you while work is happening is not a control plane.

**This is not parallelism.** `crew.max_concurrent` ships at **1**. Crew separates
*"its own process"* from *"at the same time"*; only the first is new. See §5.

### Validators (short-lived subagents, never see implementer reasoning)

Adversarial by design. They receive the contract slice and the diff, and run
**against the live worktree before teardown** — teardown removes the very thing
they need to read.

Under `crew` their isolation stops being a convention and becomes structural: the
worker is a separate OS process, so its reasoning is physically out of reach
rather than merely unpasted.

## 3. The validation contract

The single most load-bearing artifact in the harness.

- **Written during planning, before any code.**
- Contains executable assertions, not aspirations: commands + expected exit codes, observable behaviors, file invariants.
- Lives at `missions/<id>/contract.md`.
- Tests written *after* implementation confirm bias. The contract avoids that.
- Each feature in `plan.md` cites the contract sections it satisfies.

See [protocols/validation-contract.md](protocols/validation-contract.md) and [templates/validation-contract.md](templates/validation-contract.md).

---

## 4. Mission lifecycle

```
        ┌────────────┐
        │   INTAKE   │  user describes goal
        └─────┬──────┘
              ▼
        ┌────────────┐
        │    PLAN    │  orchestrator decomposes into features
        └─────┬──────┘
              ▼
        ┌────────────┐
        │  CONTRACT  │  orchestrator writes assertions
        └─────┬──────┘
              ▼
       ┌──────────────┐
       │ APPROVAL GATE│  ◀── only mandatory human checkpoint
       └─────┬────────┘
             ▼
       ┌──────────────────────────────────────────┐
       │              FEATURE LOOP                │
       │   ┌──────────────────────────────────┐   │
       │   │ spawn Worker (fresh ctx)         │   │
       │   │ ─ implement + commit + handoff   │   │
       │   └──────────────┬───────────────────┘   │
       │                  ▼                       │
       │   ┌──────────────────────────────────┐   │
       │   │ spawn Scrutiny Validator         │   │
       │   │ (sees contract + diff only)      │   │
       │   └──────────────┬───────────────────┘   │
       │                  ▼                       │
       │   ┌──────────────────────────────────┐   │
       │   │ spawn User-Testing Validator     │   │
       │   │ (if user-observable behavior)    │   │
       │   └──────────────┬───────────────────┘   │
       │                  ▼                       │
       │   ┌──────────────────────────────────┐   │
       │   │ decide: pass → next feature      │   │
       │   │         fail → follow-up feature │   │
       │   └──────────────┬───────────────────┘   │
       └──────────────────┼───────────────────────┘
                          ▼
                   ┌────────────┐
                   │   CLOSE    │  integration check + post-mortem + learnings
                   └────────────┘
```

---

## 5. Serial execution

> **Crew did not change this rule.** It separates *running as its own process*
> from *running at the same time as another worker* — only the first is new.
> `crew.max_concurrent` ships at 1 and `scripts/crew/spawn.sh` refuses to exceed
> it. Everything below still holds.


Features execute one at a time. Workers do not run concurrently. The next worker inherits the codebase from the previous worker **via git**.

Parallelism is allowed only for **non-conflicting, read-only work**:
- Codebase exploration
- API/library research
- Documentation reads
- Validation reviews of already-completed features

Slower on paper; correctness compounds over multi-day runs. See [protocols/serial-execution.md](protocols/serial-execution.md).

---

## 6. Structured handoffs

Every Worker subagent returns a handoff matching [templates/handoff-report.md](templates/handoff-report.md). The Orchestrator persists it at `missions/<id>/features/<n>/handoff.md`.

Required sections:
- What was implemented
- What was left undone (and why)
- Commands run + exit codes
- Issues discovered
- Whether the procedures in the spec were followed

If a worker returns free-form text without these sections, the Orchestrator treats the feature as incomplete and re-spawns with a stricter prompt.

---

## 7. Broadcast

There is no peer-to-peer agent chat. Coherence comes from broadcast:

- `missions/<id>/log.md` — append-only timeline. Orchestrator writes; everyone else can read.
- `missions/<id>/status.json` — machine-readable current state.
- `missions/<id>/contract.md` — source of truth for "done."

Workers and Validators receive relevant slices of these files via their spawn prompt. They do not chat back; they return a structured artifact.

---

## 8. Model routing

No single model is best at planning, implementation, and validation.

| Role | Strengths needed | Default model |
|------|------------------|---------------|
| Planning (Orchestrator) | Slow careful reasoning, strategic questions, constraint analysis | Opus |
| Implementation (Worker) | Code fluency and creativity, fast generation, tool use | Sonnet |
| Validation (Scrutiny) | Strict instruction-following; ideally a different provider to avoid training-data bias | Sonnet or Haiku |
| Validation (User-Testing) | Tool use, Playwright MCP browser tools | Sonnet |
| Exploration | Cheap parallel reads | Haiku |

See [protocols/model-routing.md](protocols/model-routing.md). The Agent tool accepts a `model` parameter — use it.

---

## 9. State, files, and the "harness" boundary

> **Local state now lives in four roots, none of them tracked:** `missions/`
> (specs, contracts, features, handoffs, decisions), `data/` (project registry,
> inbox, crew worktrees), `state/` (task meta and ledgers, locks, epochs,
> digests), `config/` (operator choices). See the README's "Local state" table.


The harness has **no runtime of its own**. It is:
- Markdown protocols Claude reads on entry (via [CLAUDE.md](CLAUDE.md)).
- Markdown templates Claude fills in.
- One shell script (`scripts/status.sh`) so users can inspect mission state without spending tokens. Scaffolding is done inline by Claude via the Write tool — the templates are the source of truth, not duplicated shell logic.
- An optional set of Claude Code hooks (under `hooks/`) that enforce procedures (e.g., a Stop hook that refuses to end if `status.json` is red).

The "agents" are Claude Code subagents spawned via the Agent tool. The "memory" is the filesystem.

This keeps the harness:
- **Inspectable** — every state transition is a diff.
- **Resumable** — a new session can read `status.json` and continue.
- **Portable** — copy the folder, you have the harness.

---

## 10. Continuous learning

```
   ┌─────────────┐
   │  New Task   │
   └──────┬──────┘
          ▼
   ┌─────────────┐
   │   Execute   │
   └──────┬──────┘
          ▼
   ┌─────────────┐
   │   Observe   │
   └──────┬──────┘
          ▼
   ┌─────────────┐
   │    Learn    │
   └──────┬──────┘
          ▼
   ┌─────────────┐
   │ Encode Skill│
   └──────┬──────┘
          ▼
         loop
```

Post-mortems → patterns → injected into next orchestrator prompt. See `learnings/README.md`.

---

## 11. What this is *not*

- It is not a separate runtime, daemon, or service.
- It is not a peer-to-peer agent mesh.
- It is not a generic "agent framework" — it is opinionated about Missions semantics.
- It is not a replacement for code review. It is a discipline that produces better code to review.

---

## 12. Iteration

The harness is **v1.0** (shipped 2026-05-23). See [ROADMAP.md](ROADMAP.md) for the v0.1 → v1.0 journey and Beyond v1.0 forward planning. The v0.3–v1.0 arc delivered multi-provider model routing, the continuous learning loop, parallel exploration, mission control skills, resumability, anti-template guardrails, background processing, and production infrastructure. Every mission should leave the harness slightly better than it found it.
