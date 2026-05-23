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

### Contract
- See [validation-contract.md](validation-contract.md).
- Write the contract **before** any worker is spawned.
- Prefer executable assertions (shell commands with expected exit codes) over prose.
- Cover: behavior, structure (file invariants), performance budgets if relevant, security checks.

### Approval gate
- Present `plan.md` and `contract.md` to the user.
- Wait for explicit "approved" before spawning any Worker.
- This is the **only** mandatory human gate.

### Feature loop
For each feature in order:
1. Update `status.json`: `current_feature = NNN`.
2. Append to `log.md`: `[ts] feature NNN started`.
3. Spawn a Worker subagent with [agents/worker.md](../agents/worker.md) as the prompt prefix, plus:
   - The feature `spec.md`.
   - The contract slice it must satisfy.
   - The previous feature's handoff (if any).
4. Receive the Worker's return value. Persist it at `features/NNN/handoff.md`. Validate it has all required sections (see [handoff.md](handoff.md)). If not, re-spawn.
5. Spawn a Scrutiny Validator subagent with [agents/scrutiny-validator.md](../agents/scrutiny-validator.md). It only sees the contract slice + the diff.
6. If the feature has user-observable behavior, spawn a User-Testing Validator.
7. Decide:
   - All verdicts green → mark feature done, update `status.json`, advance.
   - Any verdict red → open a **follow-up feature** (`features/NNN-followup-...`). Do not patch the existing feature in place.
8. Append to `log.md`.

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
