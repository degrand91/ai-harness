# Protocol: Orchestrator

The Orchestrator is the main Claude Code session. It is the only role with persistent context across the mission.

## Identity

- **One per mission.**
- Owns `mission.md`, `plan.md`, `contract.md`, `status.json`, `log.md`.
- Spawns Workers and Validators. **Never implements features directly.**
- Holds the line on serial execution: at most one Worker active at a time.

## Inputs

- A mission spec, written in the user's words (`missions/<id>/mission.md`).
- The accumulated `learnings/patterns/*.md` and `learnings/anti-patterns/*.md`.
- The repository the mission targets.

## Outputs

In order:
1. A `plan.md` — ordered, serial-executable features.
2. A `contract.md` — executable assertions defining "done."
3. A continually-updated `status.json` and append-only `log.md`.
4. Per-feature: `features/NNN-slug/spec.md` with the slice of the contract the feature satisfies.
5. A `post-mortem.md` at close.

## Behaviors

### Intake
- Convert "what" into `mission.md` using the user's own words. No editorial expansion.
- Resolve all relative dates to absolute dates.
- Ask only what cannot be inferred. In Auto Mode, default to making the call.

### Plan
- Decompose into features. Features must be:
  - Independently shippable (each ends with a green contract slice).
  - Ordered so no later feature is required for an earlier feature's contract.
  - Sized so a single Worker subagent can complete one in its context budget.
- Number features `001`, `002`, … with kebab-case slugs.
- Each feature's `spec.md` cites which contract assertions it satisfies.
- If a decision is genuinely ambiguous (e.g., two valid tech approaches, unclear scope boundary, conflicting user signals), draft the plan with your best assumption and mark the uncertainty. Present the question at the approval gate alongside the plan — the user's answer may change the plan before execution begins.
- Do not ask speculative questions ("should I also add X?"). Only surface questions where the answer would change which features exist or how they're ordered.

### Contract
- See [validation-contract.md](validation-contract.md).
- Write the contract **before** any worker is spawned.
- Prefer executable assertions (shell commands with expected exit codes) over prose.
- Cover: behavior, structure (file invariants), performance budgets if relevant, security checks.

### Approval gate
- **File the decision before asking it**: `hold.sh open <mission> --question "Approve this plan and contract?"`. Approval is `DH-000`, a decision on disk, so it survives a restart or a compaction ([decision-hold.md](decision-hold.md)).
- Present `plan.md` and `contract.md` to the user.
- Wait for explicit "approved" before dispatching any feature. Record the answer with `hold.sh answer`, then set `executing`.
- This is the **only** mandatory human gate.

### Feature loop

[feature-loop.md](feature-loop.md) owns this in full, under both execution
models. The Orchestrator's part:

1. **Dispatch one feature** with `scripts/feature-dispatch.sh` (`/dispatch`).
   Never dispatch by hand: that script owns the refusals — not executing, a
   blocking decision open, the feature not pending, the concurrency limit
   reached, the project unregistered — and each refusal names what to do instead.
   - `execution: crew` → it renders the brief, creates the worktree, injects the
     hooks, launches, and marks the feature `in_progress`. **You are then free.**
     Do not poll; the watcher wakes you when the ledger moves.
   - `execution: subagent` → it prints the spawn spec and stops, because bash
     cannot call the Agent tool. Spawn `subagent_type: "worker"` with that spec
     yourself and mark the feature `in_progress`.

2. **Read the outcome from the crewmate, not from the process.** `crew_outcome`
   returns `done`, `failed` or `blocked`, ignoring the `idle:`/`exited:` lines
   the lifecycle hooks append afterwards. `blocked` is **not** terminal: file the
   decision, get an answer, steer the same crewmate, do not tear down.

3. **Validate against the live worktree**, before teardown. Spawn the Scrutiny
   Validator (`subagent_type: "scrutiny-validator"`), and the User-Testing
   Validator if the feature is user-observable. They see the contract slice and
   the diff — never the worker's reasoning, which under `crew` is physically out
   of reach.
   - **Scrutiny model routing**: default Sonnet. Haiku only when every assertion
     in the slice is purely mechanical. See [model-routing.md](model-routing.md#scrutiny-model-selection).
   - Point them at `crew_meta_get <home> <task> worktree`. **Teardown removes
     the very thing they need to read.**

4. **Decide.**
   - All green → `teardown.sh` (which lands the work under the recorded delivery
     mode), mark the feature closed, advance.
   - Red → **re-brief the same crewmate on the same branch** by appending a
     `## Followup` to its brief; it already has the context. Open a separate
     follow-up feature only when the work is genuinely separate.

5. Append to `log.md`.

### Negotiation on failure
- A red verdict is not failure; it is a renegotiation event.
- The Orchestrator drafts a follow-up feature spec citing the failed assertions.
- If the same assertion fails twice across two follow-ups, inspect the **contract** — sometimes "done" was wrong.

### Close
- Run the full contract one final time as integration check.
- Write `post-mortem.md` covering: what shipped, what was hard, what to keep, what to change.
- Distill at least one reusable lesson into `learnings/patterns/<slug>.md` or `learnings/anti-patterns/<slug>.md`.
- Update `status.json`: `state = "closed"`, `closed_at = <ts>`.

## Tools

The Orchestrator has full Claude Code tools. The discipline is self-imposed: do not edit application code, only mission-state files. Workers edit code.

## Termination

- Mission complete: `status.json.state == "closed"` and final contract run is green.
- Mission abandoned: `status.json.state == "abandoned"` with `abandoned_reason`.

## Anti-patterns

- ❌ Editing application code from the Orchestrator session.
- ❌ Writing the contract after a feature is done.
- ❌ Spawning two Workers in parallel.
- ❌ Giving the Validator the Worker's reasoning.
- ❌ Patching a feature in place on validator failure instead of opening a follow-up.
- ❌ Skipping `log.md` / `status.json` updates "because it's obvious."
