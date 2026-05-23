---
name: contract-check
description: Re-run every executable assertion in a mission's contract.md and write a machine-readable verdict. Use as the integration check at mission close, or any time you want to confirm the repo still satisfies the contract. Safe to invoke any time — read-only against application code.
argument-hint: <mission-id>
allowed-tools: Read, Bash, Grep, Glob
---

## Argument
Mission id: $ARGUMENTS

## Contract
@missions/$ARGUMENTS/contract.md

---

Re-run every executable assertion in the contract above and write a verdict.

## Procedure

1. Parse `contract.md` for assertion blocks. Each looks like:
   ```
   ### C-XXX — executable — Owner: F<NN>
   **Statement.** ...
   **Verification.**
   ```bash
   <command>
   # expected: exit 0
   ```
   ```

2. For each executable assertion: run the command in a Bash call. Capture exit code and the last ~10 lines of output.

3. For each behavioral assertion: state `requires-human` and quote the assertion text — behavioral assertions are not auto-runnable.

4. Compute overall verdict: **green** iff every executable assertion exits 0 and no behavioral assertion is flagged red by a recent Scrutiny verdict (look at `missions/$ARGUMENTS/features/*/scrutiny.md` if relevant).

5. Write a verdict file at `missions/$ARGUMENTS/integration-check.md` matching this shape:

```markdown
## Integration check: <mission-id> — <green|red>

Ran at: <ISO timestamp>

### Assertions

| ID | Type | Result | Evidence |
|----|------|--------|----------|
| C-001 | executable | pass | exit 0 |
| C-002 | executable | fail | exit 1; "ReferenceError: ..." |
| C-003 | behavioral | requires-human | (statement) |

### Failures

(if any — one block per failure with: assertion ID, command, full output, suggested follow-up scope)
```

6. Append a one-line summary to the mission log (`missions/$ARGUMENTS/log.md`):
   ```
   [<ts>] integration-check ran — verdict=<green|red> — <N> assertions, <M> failures
   ```

7. Surface the verdict path + summary to the caller. If red, the Orchestrator decides whether to open follow-up features or amend the contract.

## Hard rules

- Do not modify application code or the contract from this skill.
- Run every assertion. Don't sample.
- If an assertion is malformed (un-runnable), report `skipped — malformed` and explain. The Orchestrator owns the contract; you flag, they fix.
