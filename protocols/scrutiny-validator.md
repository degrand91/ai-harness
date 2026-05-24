# Protocol: Scrutiny Validator

The Scrutiny Validator is an adversarial subagent that verifies a completed feature against the validation contract. It has **never seen the Worker's code or reasoning**.

## Identity

- **One per feature** (sometimes more, on follow-ups).
- Fresh context.
- Sees only: the contract slice, the diff, and the repository at HEAD.
- Returns a verdict. Is destroyed.

## Inputs

A single self-contained prompt containing:
- The role prompt is loaded automatically from [.claude/agents/scrutiny-validator.md](../.claude/agents/scrutiny-validator.md) (registered subagent). The Orchestrator passes only the task.
- The full contract slice the feature must satisfy.
- The git diff of the feature's commit(s).
- The commands declared in the contract (e.g. `pnpm test`, `pytest`, `cargo test`, `npm run lint`).

The Scrutiny Validator does **not** receive:
- The Worker's handoff narrative.
- `log.md`.
- The Orchestrator's plan rationale.

This isolation is intentional — the verifier must not inherit the implementer's frame.

## Outputs

A verdict file matching [templates/validation-verdict.md](../templates/validation-verdict.md):

- Per-assertion result: `pass` / `fail` / `skipped` with command output excerpt.
- Overall: `green` / `red`.
- If red: a structured "follow-up spec" the Orchestrator can use to negotiate the next feature.

## Behaviors

### Run every assertion
- Don't sample. Don't trust prior runs. Re-execute every command in the contract slice.
- Capture exit codes and a relevant snippet of output for each.

### Code review against the contract
- Open the diff. For each contract assertion of the form "code structure must ...":
  - Verify by reading the diff, not the worker's claim.
- Flag:
  - Mutation patterns where the contract requires immutable updates.
  - Hardcoded secrets, magic numbers, swallowed errors.
  - Coverage gaps in tests where the contract requires coverage.
  - Tests written by the worker that don't actually exercise the contract (i.e., test-laundering).

### Adversarial mindset
- Default verdict is **red** unless every assertion passes.
- Prefer false-positive (flagging something that's actually fine) over false-negative (missing a real defect).

### Write the follow-up spec on red
- For each failed assertion, draft a minimal follow-up feature description.
- The Orchestrator may consolidate them. The Validator's job is to write each one independently.

## Tools

- Read, Grep, Glob, Bash (for running tests/lints).
- No Write, no Edit — the Validator cannot fix what it finds.

## Termination

- All assertions evaluated.
- Verdict file written.
- If a contract assertion is malformed (un-runnable), the Validator reports `skipped` with reason — the Orchestrator must fix the contract.

## Tool-use integrity

Every executable assertion in the contract slice must be run via the Bash tool. This is non-negotiable.

**Mandate:** The Scrutiny Validator must invoke the Bash tool for every assertion that has an expected exit code or produces observable output. It must not predict, guess, or fabricate results based on reading the diff alone.

**Rationale:** A validator that does not run assertions provides zero verification value. Worse, a validator that fabricates `pass` verdicts actively misleads the Orchestrator into shipping defective code. The entire Creator-Verifier strategy depends on the verifier independently executing the same checks the contract defines.

**Guard:** The Orchestrator checks the `tool_uses` count on the Validator's return. If the count is zero and the verdict contains assertion results, the results were fabricated. The Orchestrator must re-spawn the Validator with escalated instructions noting the protocol violation.

**Detection heuristic:** If the verdict contains assertion results (pass/fail) but the Validator's tool_uses count is 0, treat all results as fabricated and the verdict as invalid. Re-spawn.

**Blocked assertions:** If a command cannot be run (missing binary, permission error, unreachable service), the Validator reports the assertion as `blocked` with a reason — not `pass` and not `fail`. A `blocked` result is honest; a fabricated `pass` is a protocol violation.

**Anti-pattern reference:** See [`learnings/anti-patterns/haiku-scrutiny-hallucination.md`](../learnings/anti-patterns/haiku-scrutiny-hallucination.md) for a documented case of this failure mode, including how it manifested and how it was detected.

## Anti-patterns

- ❌ Reading the Worker's handoff before deciding.
- ❌ Editing code to fix what was found.
- ❌ Marking an assertion `pass` because the Worker said so.
- ❌ Skipping an assertion as "obviously fine."
- ❌ Bundling all failures into one follow-up spec — write them out independently so the Orchestrator can sequence them.
- ❌ Fabricating Bash command outputs without running the Bash tool — zero tool calls with assertion verdicts is always a protocol violation.
