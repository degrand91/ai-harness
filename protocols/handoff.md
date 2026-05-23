# Protocol: Handoff

The handoff is the only artifact that crosses agent boundaries. Workers produce them; the Orchestrator persists them; the next Worker (sometimes) reads the previous one for context continuity.

## Required sections

Every handoff must contain, in this order:

1. **What was implemented** — concrete bullets.
2. **What was left undone** — bullets with reasons, or "Nothing".
3. **Commands run + exit codes** — every command, every exit code, with a one-line note.
4. **Issues discovered** — anything the spec/contract didn't anticipate.
5. **Procedures followed** — y/n per procedure listed in the spec.
6. **Commits** — sha + message for each commit produced.

See [templates/handoff-report.md](../templates/handoff-report.md).

## Non-standard handoffs

A Worker may also return:

- **SPEC-CLARIFICATION** handoff — the spec was ambiguous. Worker did not edit. Lists options and a recommendation.
- **BLOCKED** handoff — environment/credentials/dependency blocker. Worker did not edit. Lists what's needed.

Both must use the templates above (no free-form prose).

## What the Orchestrator does on receipt

1. Persist to `missions/<id>/features/NNN-<slug>/handoff.md`.
2. Validate sections present. If not, re-spawn the Worker with a stricter prompt.
3. Update `features/NNN/status.json` and append to `log.md`.
4. Decide:
   - Standard handoff with contract-slice green locally → proceed to Scrutiny Validator.
   - SPEC-CLARIFICATION → revise the spec (or contract slice) and re-spawn a Worker.
   - BLOCKED → escalate to the user with the blocker contents.

## What downstream agents see

- **Next Worker** (next feature): receives the previous handoff under "previous feature context" — but this is informational. The codebase state lives in git.
- **Scrutiny Validator**: **does not see the handoff**. Sees the contract slice and the diff.
- **User-Testing Validator**: does not see the handoff. Sees the contract slice and the launch recipe.

This asymmetry is intentional — verifiers must not inherit the implementer's frame.

## Anti-patterns

- ❌ Free-form prose handoffs.
- ❌ "Procedures followed: yes" with no notes — list them by name.
- ❌ Handoffs that report "0 issues" when there were obvious ones.
- ❌ Worker reading `log.md` or other features' handoffs.
- ❌ Showing the handoff to a Validator.
