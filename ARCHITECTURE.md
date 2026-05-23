# Architecture

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

```
                  ┌─────────────────────────────────────┐
                  │            ORCHESTRATOR             │
                  │ Plans features, milestones, and the │
                  │         validation contract         │
                  └──────────────┬──────────────────────┘
                                 │
                ┌────────────────┴────────────────┐
                ▼                                 ▼
       ┌───────────────────┐            ┌────────────────────┐
       │      WORKERS      │            │     VALIDATORS     │
       │ Fresh context per │            │ Adversarial. Have  │
       │ feature.          │            │ never seen the     │
       │ Implement, commit │            │ code before.       │
       │ via git, hand off.│            │                    │
       └───────────────────┘            └────────────────────┘
```

### Orchestrator (you, the main Claude session)
- Reads the mission spec + accumulated `learnings/`.
- Decomposes the goal into ordered features.
- Writes the **validation contract** before any code is written.
- Waits at the one mandatory human gate (plan + contract approval).
- Spawns Workers and Validators, never implements features itself.
- Owns `status.json` and `log.md` (broadcast).
- Decides whether to open a follow-up feature when validation fails (negotiation).

### Workers (short-lived subagents, one per feature)
- Receive: feature spec + relevant contract slice + handoff from previous feature (if any).
- Operate with **fresh context** — they do not see the orchestrator's chat or earlier worker reasoning.
- Inherit the codebase via git, not via memory.
- Implement, run tests, commit, return a structured handoff.

### Validators (short-lived subagents, never see implementer reasoning)
- **Scrutiny Validator** — runs lint/typecheck/test, performs code review, checks contract assertions one by one.
- **User-Testing Validator** — launches the app, exercises flows like a QA engineer (Playwright, computer-use, manual smoke).
- Sees: the validation contract and the diff. Does **not** see the worker's reasoning or handoff narrative.
- Returns a verdict: green / red / red-with-followup-spec.

---

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
| Validation (User-Testing) | Tool use, browser/computer-use | Sonnet |
| Exploration | Cheap parallel reads | Haiku |

See [protocols/model-routing.md](protocols/model-routing.md). The Agent tool accepts a `model` parameter — use it.

---

## 9. State, files, and the "harness" boundary

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

The harness is v0.1. See [ROADMAP.md](ROADMAP.md) for the v0.2 → v1.0 path. Every mission should leave the harness slightly better than it found it.
