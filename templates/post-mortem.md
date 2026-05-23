# Post-mortem Template

> Saved at `missions/<id>/post-mortem.md`. Written by the Orchestrator at mission close. Every mission must have one, even on abandonment.

---

# Post-mortem: <mission id>

**State at close:** closed | abandoned
**Started:** `<ISO>`
**Closed:** `<ISO>`
**Wall-clock duration:** `<X days Y hours>`
**Active worker-hours (sum of subagent execution):** `<approx>`

## Summary

One paragraph. What did the mission deliver?

## Features executed

| ID | Slug | First-pass result | Follow-ups | Notes |
|----|------|-------------------|------------|-------|
| F001 | ... | green | 0 | |
| F002 | ... | red | 2 | first contract assertion was ambiguous |
| F003 | ... | green | 0 | |

## Validator failures by assertion

Which assertions tripped, and how often?

| Assertion | Trips | Reason |
|-----------|-------|--------|
| C-006 (no hardcoded secrets) | 2 | model kept inlining test fixture |

## Cost & tokens

| Role | Model | Provider | Tokens (in/out) | Approx cost |
|------|-------|----------|-----------------|------------|
| Orchestrator | Opus | claude | ... | ... |
| Worker (×N) | Sonnet | claude | ... | ... |
| Scrutiny Validator (×N) | Haiku | claude | ... | ... |
| User-Testing Validator (×M) | Sonnet | claude | ... | ... |
| Explorer (×K) | Haiku | claude | ... | ... |
| **Total** | | | | **$X** |

When `HARNESS_EXTERNAL_VALIDATOR_PROVIDER` is set, the Scrutiny Validator runs on an external provider. Add a separate row for those tokens tagged with the provider name (e.g. `Scrutiny Validator (external) | n/a | openai | … | …`), so the worker-vs-validator provider split is visible across v0.3-and-later post-mortems.

## What worked

- bullet (specific, not generic)

## What was hard

- bullet — what slowed the mission down

## What to keep

- bullet (becomes a candidate `learnings/patterns/<slug>.md` entry)

## What to change

- bullet — proposed protocol / template / prompt edits.
- If significant, file under `learnings/proposals/<slug>.md` for the next mission to consider.

## Anti-patterns observed

- bullet (becomes a candidate `learnings/anti-patterns/<slug>.md` entry)

## Distilled learnings

At least one of:
- New entry in `learnings/patterns/<slug>.md`
- New entry in `learnings/anti-patterns/<slug>.md`

Linked here: `[[slug]]` references for cross-mission searchability.

## Signed off

- [ ] User reviewed
- Reviewed at: `<ISO>`
