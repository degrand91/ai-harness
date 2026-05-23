# Post-mortem: 2026-05-22-add-marker

**State at close:** closed
**Started:** `2026-05-22T23:49:14Z`
**Closed:** `2026-05-22T23:50:30Z`
**Wall-clock duration:** ~80 seconds (smoke test)
**Active subagent runtime (sum):** Worker 50s + Scrutiny 25s ≈ 75s

## Summary

Smoke-test mission to validate end-to-end harness mechanics on a trivial target. Created `MARKER.md` containing `2026-05-22` in `/tmp/harness-test`, with one conventional commit. Full lifecycle exercised: intake → plan → contract → approval gate (pre-approved by user for the demo) → Worker subagent → Scrutiny Validator subagent → integration check → close.

## Features executed

| ID | Slug | First-pass result | Follow-ups | Notes |
|----|------|-------------------|------------|-------|
| F001 | add-marker | green | 0 | Worker on Sonnet, Scrutiny on Haiku. Both first-try. |

## Validator failures by assertion

None. All 5 contract assertions (C-001..C-005) passed.

## Cost & tokens

| Role | Model | Tokens (in+out total) | Tool uses | Wall time |
|------|-------|-----------------------|-----------|-----------|
| Orchestrator | Opus (this session) | not isolated (mixed with prior harness work) | — | — |
| Worker (F001) | Sonnet | 30,450 | 9 | 49.9s |
| Scrutiny Validator (F001) | Haiku | 39,626 | 8 | 25.6s |
| User-Testing Validator | — | (skipped — no user-observable behavior) | — | — |
| Explorer | — | (skipped — trivial mission) | — | — |

Notable: Haiku Scrutiny used more tokens than Sonnet Worker. Inputs were inflated by the inline contract slice + the role prompt; this is expected for short missions where prompt overhead dominates.

## What worked

- **Inline scaffolding via Write tool was clean.** No shell script needed. Fewer steps, fewer surfaces.
- **Worker handoff was returned in the exact required shape** on the first try — the role prompt's "return this and nothing else" framing held.
- **Asymmetric isolation worked.** The Scrutiny Validator received only the contract and the diff (not the Worker's handoff or reasoning), yet reached the correct verdict.
- **`status.sh` proved useful immediately** — gave a clean Claude-free view of mission state right after scaffolding.

## What was hard

- Nothing slowed this mission. It's a smoke test.

## What to keep

- The Worker role prompt's strict "return only the handoff markdown" rule and the explicit table-form sections — kept the handoff machine-parseable on the first try.
- Running the Scrutiny Validator on Haiku — fast, cheap, correct on a contract this mechanical.

## What to change

- **Scrutiny Validator added a one-paragraph prose preamble before the verdict block**, in violation of the role prompt. The harness should either:
  1. Tighten the role prompt with an explicit "do not include any text before the verdict block" line, or
  2. Persist by extracting only the `## Feature:` markdown block (defensive parsing).
- Probably both. Filed as `learnings/anti-patterns/validator-prose-preamble.md`.

## Anti-patterns observed

- See above. Validator prose preamble.

## Distilled learnings

- `learnings/anti-patterns/validator-prose-preamble.md` — captures the observed failure mode and the fix.

## Signed off

- [x] User reviewed (smoke test, surfaced to user at close)
- Reviewed at: `2026-05-22T23:50:30Z`
