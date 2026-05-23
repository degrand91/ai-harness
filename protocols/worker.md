# Protocol: Worker

A Worker is a short-lived Claude Code subagent that implements exactly one feature.

## Identity

- **One per feature.** Spawned by the Orchestrator via the Agent tool.
- **Fresh context.** Does not see the Orchestrator's chat or any prior Worker.
- **Code inheritance via git only.** Reads the repository state at HEAD.
- Returns a structured handoff and is destroyed.

## Inputs

The Orchestrator passes a single self-contained prompt containing:
- The role prompt from [agents/worker.md](../agents/worker.md).
- The feature `spec.md`.
- The slice of `contract.md` this feature must satisfy.
- (Optional) The previous feature's `handoff.md` for context continuity.

The Worker reads the repo directly. It does **not** read `log.md` or other features' `handoff.md`.

## Outputs

A return value matching [templates/handoff-report.md](../templates/handoff-report.md). Required sections:

1. **What was implemented** — bullet list, concrete.
2. **What was left undone** — and why.
3. **Commands run + exit codes** — every command, every exit code.
4. **Issues discovered** — anything the contract didn't anticipate.
5. **Whether procedures were followed** — y/n per procedure listed in the spec, with notes.

If the Worker returns free-form text without these sections, the Orchestrator treats the feature as incomplete and re-spawns.

## Behaviors

### Read the spec end-to-end before editing
- Confirm the feature's contract slice is unambiguous.
- If genuinely ambiguous, return early with a "spec-clarification" handoff. Do **not** guess and ship.

### Plan locally, then implement
- The Worker may use its own TodoWrite/scratch reasoning internally.
- Implementation should pass the contract slice when complete.

### Commit through git
- One commit per feature, conventional commits format.
- Commit message references the feature slug: `feat(<slug>): <summary>`.
- No `--no-verify`. Pre-commit hook failures are issues to report, not bypass.

### Run the contract slice before handing off
- The Worker must execute the contract slice itself and record exit codes in the handoff.
- The Worker is not the Validator — passing locally does not mean validation will pass. But green-locally is a prerequisite for handoff.

### Stay in lane
- Edits limited to files within the feature's scope as declared in `spec.md`.
- Touching files outside scope must be flagged in "Issues discovered."

## Tools

A Worker should be spawned as a `general-purpose` subagent (full tools). It needs Read, Write, Edit, Bash, Grep, Glob.

## Termination

The Worker returns when:
- Contract slice runs green locally **and** handoff is complete; or
- Spec is genuinely ambiguous → returns a spec-clarification handoff; or
- Blocked on missing credentials/environment → returns a blocker handoff.

## Anti-patterns

- ❌ Returning prose instead of a structured handoff.
- ❌ Editing files outside the feature scope without flagging.
- ❌ Skipping `--no-verify` to push through a failing pre-commit.
- ❌ Modifying `contract.md` to make the feature pass.
- ❌ Reading `log.md` or other features' handoffs.
- ❌ Asking the user a question. The Worker has no human channel — escalate via the handoff.
