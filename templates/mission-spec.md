# Mission Spec Template

> Saved at `missions/<id>/mission.md`. The Orchestrator authors this from the user's words. Do not editorialise — capture intent, not your interpretation of it.

---

# Mission: <Short title in user's framing>

**ID:** `YYYY-MM-DD-<kebab-slug>`
**Started:** `<ISO timestamp>`
**Author (user):** `<name or email>`
**Repository:** `<absolute path>`
**Branch:** `<branch base or "create new">`

## Goal (in the user's words)

> Verbatim, or as close as possible.

## Why (motivation)

- Bullet from the conversation. What's the underlying need this serves?

## Non-goals

- Explicit out-of-scope items. Things the user said NO to, or things the Orchestrator inferred should be deferred.

## Constraints

- Tech stack constraints (must use X, must not use Y).
- Time constraints (ship by, no longer than).
- Cost/budget constraints (token budget, dependency budget).
- Operational constraints (must not change DB schema, must preserve URL structure, etc.).

## Inputs from the user

- Files, URLs, references the user provided.
- Test accounts, credentials (note where they live; **never** paste secrets here).

## Definition of "delivered"

- One-paragraph summary the user agrees with. The contract is the *formal* version; this is the plain-English version.

## Risks the user flagged

- Things the user is nervous about. The Orchestrator must address each in the plan.

## Approval

- [ ] Mission spec reviewed and approved by user
- Approved at: `<ISO timestamp>`
