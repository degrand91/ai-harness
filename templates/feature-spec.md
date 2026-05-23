# Feature Spec Template

> Saved at `missions/<id>/features/NNN-<slug>/spec.md`. One per feature. Written by the Orchestrator before spawning the Worker.

---

# Feature: F<NNN> — <slug>

## Goal

One sentence. What this feature accomplishes.

## Scope

Files / modules / surfaces this feature may touch:
- `path/to/...`
- `path/to/...`

Out of scope for this feature (the Worker must not edit these, even if tempting):
- `path/...`

## Contract slice

This feature is responsible for satisfying these assertions from `contract.md`:

- **C-001:** *(paste statement verbatim)*
- **C-007:** *(paste statement verbatim)*

> Workers and Validators receive only this slice, not the full contract.

## Procedures (the Worker must follow these, and report y/n in the handoff)

- [ ] Write failing tests before implementation (TDD).
- [ ] Run `<typecheck command>` after each significant edit.
- [ ] Use existing utilities in `src/lib/` instead of duplicating logic.
- [ ] Commit with conventional commit message `feat(<slug>): <summary>`.
- [ ] (mission-specific procedures here)

## Inputs the Worker has

- Previous feature's `handoff.md` (informational only).
- This `spec.md`.
- The contract slice above.

## Expected outputs

- Code changes constrained to the declared scope.
- One git commit.
- A handoff matching `templates/handoff-report.md`.

## User-observable behavior?

`yes` or `no`. If yes, a User-Testing Validator will also run.

## Notes / hints (optional)

Anything the Orchestrator wants the Worker to know that isn't in the contract — references, gotchas, prior-art links.
