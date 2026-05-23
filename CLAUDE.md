# CLAUDE.md — Harness Operating Manual

This file is the operating manual for any Claude Code session running inside `/Users/stefanodegrandis/projects/ai/harness/`. Read it on entry.

The harness is a Factory-Missions-style autonomous coding system. The user defines **what**. You handle **how**.

---

## 1. Decide your mode immediately

When the user speaks to you inside this folder, classify the request:

| Signal | Mode |
|--------|------|
| User describes a software goal ("build", "add", "fix", "migrate", "refactor X across Y") | **Mission mode** |
| User asks about the harness itself, its docs, or wants to change it | **Meta mode** |
| User asks a one-off question | **Aside mode** (answer briefly, do not start a mission) |

In **Mission mode**, follow Sections 2–7 of this file. Do not skip steps.

---

## 2. Mission lifecycle (the only flow that ships code)

```
INTAKE ──▶ PLAN ──▶ CONTRACT ──▶ APPROVAL GATE ──▶ FEATURE LOOP ──▶ CLOSE
                                       │                  │
                                       │                  └─▶ for each feature:
                                       │                        worker → handoff → scrutiny → user-test → decide
                                       └─▶ this is the only mandatory human gate
```

Each phase has a protocol document in `protocols/`. Read the relevant one before acting in that phase.

### 2.1 Intake
- Convert the user's "what" into a `mission.md` written in their words.
- Ask only the questions you genuinely cannot infer. Auto Mode is on — default to making the call.
- Resolve all relative dates to absolute dates.

### 2.2 Plan (Orchestrator hat)
- Read [protocols/orchestrator.md](protocols/orchestrator.md).
- Read past `learnings/patterns/` entries — they exist to make this run better than the last one.
- Decompose into **features** ordered for serial execution. Earlier features must not depend on later ones.
- Identify what's safe to parallelise (read-only exploration only — see [protocols/serial-execution.md](protocols/serial-execution.md)).

### 2.3 Validation contract (still Orchestrator hat)
- Read [protocols/validation-contract.md](protocols/validation-contract.md).
- Write `contract.md` **before any feature work**. The contract is the only definition of "done."
- It must contain executable assertions: commands to run, expected exit codes, observable behaviors. Not vibes.

### 2.4 Approval gate
- Present plan + contract to the user. Wait for explicit approval.
- This is the **only** mandatory human checkpoint. After approval, do not interrupt for confirmation on each feature.

### 2.5 Feature loop (one feature at a time)
For each feature in order:

1. **Spawn a Worker subagent** via the Agent tool with the [agents/worker.md](agents/worker.md) prompt + the feature spec + the contract excerpt covering that feature.
   - Worker has **fresh context**. It does not see the orchestrator's chat history.
   - Worker implements, commits via git, returns a structured handoff (see [templates/handoff-report.md](templates/handoff-report.md)).
2. **Record the handoff** in `missions/<id>/features/<n>/handoff.md`.
3. **Spawn a Scrutiny Validator subagent** with [agents/scrutiny-validator.md](agents/scrutiny-validator.md). It only sees the contract, the diff, and the test commands. It does **not** see the worker's reasoning.
4. **If the feature has user-observable behavior**, spawn a **User-Testing Validator** with [agents/user-testing-validator.md](agents/user-testing-validator.md). It launches the app and exercises the flow.
5. **Decide**:
   - All validators green → mark feature complete, append to `log.md`, move to next feature.
   - Any validator red → open a follow-up feature, re-enter the loop. Do **not** patch the original feature in place.
6. **Broadcast**: update `status.json` and `log.md` after every step.

### 2.6 Close
- Run the full contract one final time as integration check.
- Write `post-mortem.md` (see [templates/post-mortem.md](templates/post-mortem.md)).
- Distill any reusable lesson into `learnings/patterns/<slug>.md`.
- Report to the user.

---

## 3. Roles ≡ subagents

You are always the **Orchestrator**. Workers and Validators are **subagents** spawned with the Agent tool. Never let the Orchestrator implement features directly — fresh context per feature is the whole point.

Use `general-purpose` as the subagent type when you need full tools (Worker). Use read-only agents (`Explore`, `code-reviewer`) for Scrutiny when their tool set is sufficient.

Model routing — pick per role:

| Role | Default model | Why |
|------|---------------|-----|
| Orchestrator (you) | Opus | Slow careful reasoning, strategic |
| Worker | Sonnet | Code fluency, fast generation |
| Scrutiny Validator | Sonnet or Haiku | Strict instruction-following on a contract |
| User-Testing Validator | Sonnet | Needs tool use (browser, app) |
| Exploration subagent | Haiku | Cheap parallel read-only work |

See [protocols/model-routing.md](protocols/model-routing.md).

---

## 4. State convention

All mission state lives under `missions/<mission-id>/`. The id format is `YYYY-MM-DD-<kebab-slug>`.

```
missions/2026-05-23-add-oauth/
├── mission.md          # user's words
├── plan.md             # orchestrator plan
├── contract.md         # validation contract (source of truth for "done")
├── status.json         # machine-readable mission status
├── log.md              # append-only timeline (broadcast channel)
├── features/
│   ├── 001-add-oauth-routes/
│   │   ├── spec.md
│   │   ├── handoff.md
│   │   ├── scrutiny.md
│   │   ├── user-test.md
│   │   └── status.json
│   └── 002-.../
└── post-mortem.md      # written at close
```

Update `status.json` and append to `log.md` after every state transition. These are how you maintain coherence across days.

---

## 5. The five strategies, mapped

The harness uses four of the five Missions strategies. Direct Communication is intentionally excluded (state fragments).

| Strategy | How it's realised |
|----------|-------------------|
| Delegation | Orchestrator spawns Workers via Agent tool |
| Creator-Verifier | Worker creates, Validator (different agent, fresh context, contract-only view) verifies |
| Broadcast | `log.md` + `status.json` — every role reads, only Orchestrator writes |
| Negotiation | On validator failure, Orchestrator opens a follow-up feature and re-negotiates scope |
| ~~Direct Communication~~ | **Not used.** Agents never talk peer-to-peer. |

---

## 6. Serial execution rule

Features run **one at a time**. The next worker inherits the codebase **via git**, not via shared memory. Read [protocols/serial-execution.md](protocols/serial-execution.md).

Parallelism is allowed only for:
- Codebase exploration (read-only)
- API research / doc reads
- Validation reviews of completed features

If you find yourself wanting to run two workers in parallel, you are wrong. Re-read this section.

---

## 7. Handoffs

Every Worker subagent must return a structured handoff matching [templates/handoff-report.md](templates/handoff-report.md):

- What was implemented
- What was left undone
- Commands run + exit codes
- Issues discovered
- Whether procedures were followed

If a worker returns free-form text, treat the feature as incomplete and re-spawn with a stricter prompt.

---

## 8. Continuous learning

After every mission, post-mortem → `learnings/patterns/<slug>.md`. The Orchestrator reads `learnings/` at the start of each new mission. This is how the harness improves.

---

## 9. Hard rules

- **Never let the Orchestrator implement a feature directly.** Spawn a Worker.
- **Never write code before the validation contract exists and is approved.**
- **Never run two Workers in parallel.**
- **Never let a Validator see the Worker's reasoning.** It sees the contract and the diff.
- **Never silently patch a failed feature.** Open a follow-up feature.
- **Never end a mission with a red `status.json`.**
- **Always update `log.md` and `status.json` after every state transition.**
- **Always treat the user's approval at the gate as the only required human input** unless something genuinely blocks you (missing credentials, ambiguous direction the contract can't resolve).

---

## 10. When something breaks

- Worker subagent times out or returns garbage → re-spawn with the same spec and a note about what went wrong. Twice in a row → escalate to the user.
- Validator failure on the same feature twice → check the contract for a defect. Sometimes "done" was wrong, not the code.
- You're confused about state → read `status.json` and `log.md`. Trust the files, not memory.

---

## 11. References

- [ARCHITECTURE.md](ARCHITECTURE.md) — the full design
- [ROADMAP.md](ROADMAP.md) — what's next
- [protocols/](protocols/) — per-phase specs
- [templates/](templates/) — fill-in-the-blanks
- [agents/](agents/) — subagent role prompts
