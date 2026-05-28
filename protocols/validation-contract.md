# Protocol: Validation Contract

The contract is the single most load-bearing artifact in the harness. It defines what "done" means **before any code is written**.

> Tests written after implementation don't catch bugs — they confirm decisions.

## When it is written

- During the `contract` state of the lifecycle.
- **Before** any Worker is spawned.
- By the Orchestrator, with the user reviewing it at the approval gate.

## Structure

Each assertion has:
- **ID** — `C-001`, `C-002`, …
- **Type** — `executable` or `behavioral`.
- **Owner** — which feature satisfies it (filled in later when the plan is final).
- **Statement** — what must be true.
- **Verification** — for executable: the command and expected exit code. For behavioral: how a reader inspects the diff.

```markdown
### C-007 — Type: executable — Owner: F002

**Statement.** The `pnpm test` suite passes with no warnings.

**Verification.**
```bash
pnpm test
# expected: exit 0; no lines containing "warning"
```
```

```markdown
### C-008 — Type: behavioral — Owner: F002

**Statement.** No mutation of inputs in `src/auth/session.ts`. All updates return new objects.

**Verification.** Reader scans `src/auth/session.ts` diff. Any assignment of the form `obj.x = y` against a function parameter fails this assertion.
```

## Required coverage

A contract is incomplete unless it has at least:

- **Build/typecheck assertions.** The code compiles cleanly.
- **Test assertions.** A named test command exits 0.
- **Behavioral assertions** for each significant user-observable flow.
- **Negative assertions** — at least one "this must NOT happen" (no secrets, no swallowed errors, no console.log in production paths).
- **Structural invariants** specific to the mission — e.g. "no file in `src/` exceeds 800 lines," "no new dependencies added without an entry in `dependencies-rationale.md`."

If a mission is user-facing, add:
- **Accessibility assertions** if relevant (keyboard nav, contrast, ARIA).
- **Performance budgets** if relevant (LCP, bundle size).

## Slicing

Each feature in `plan.md` cites the assertion IDs it satisfies. The slice handed to a Worker or Validator is just those IDs, fully expanded.

If a feature isn't tied to at least one assertion, it doesn't belong in the plan.

## Re-running

The contract is re-runnable at any time:
- At the end of each feature (Scrutiny Validator runs the slice).
- At mission close (full contract).
- During a paused-resume cycle, as the first action.

A contract that can't be re-run is malformed — the Orchestrator must fix it before continuing.

## Editing the contract mid-mission

Allowed, with discipline:
- Add new assertions when the user expands scope mid-mission → record in `log.md` as an "amendment" with timestamp and reason.
- Remove or weaken assertions only with explicit user approval.
- Never remove an assertion to make a failing feature pass. That is the highest anti-pattern in the harness.

## Anti-patterns

- ❌ "All tests pass" with no named command.
- ❌ Assertions of the form "the code is good."
- ❌ Behavioral assertions a human can't independently check.
- ❌ Editing the contract to make a feature green.
- ❌ Writing the contract after the plan is "halfway done."
- ❌ Letting a Worker write its own contract slice.
- ❌ Grep-only assertions for behavioral verification — they prove a string exists, not that the code works.
- ❌ Missing `test_command` for missions that touch application code.

## Behavioral assertions are the bar

The validation contract exists to verify behavior, not text. Assertions that grep for a string prove only that a string exists. They produce false greens — the validator passes, the feature is "done," and the actual behavior is wrong.

### The rule

Every mission that touches runtime code must have at least one assertion that:
1. Exercises the changed behavior end-to-end (call the API, render the component, run the function)
2. Captures an observable outcome (response body, exit code, side effect)
3. Fails loudly if the outcome is wrong

Grep is fine for structural checks (file exists, doc mentions topic, settings has flag). Grep is not enough for "the code works."

### When the worker can't pass behavioral assertions

If the assertion requires running the app and the worker can't run the app (no test environment, missing deps), the worker reports BLOCKED in the handoff rather than passing the assertion. The orchestrator either provisions the environment or opens a setup feature first.

### `test_command` is required for code missions

The contract preamble's `test_command` field is required when the mission touches application code. Workers run it after substantive edits — catching regressions while context is hot is dramatically cheaper than catching them at the validator pass. The only acceptable "no test_command" cases are pure documentation, configuration, or template missions.
