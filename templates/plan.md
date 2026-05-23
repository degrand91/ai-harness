# Plan Template

> Saved at `missions/<id>/plan.md`. Written by the Orchestrator after intake, before the contract.

---

# Plan: <mission id>

## Overview

One short paragraph. What is the path from where the repo is now to "delivered"?

## Features (in serial execution order)

Each feature is a self-contained unit a single Worker subagent can implement. Numbered for order.

### F001 — <slug>

- **Goal:** one sentence.
- **Scope (files/areas):** explicit paths or globs.
- **Out of scope for this feature:** explicit.
- **Contract assertions satisfied:** `C-001, C-003, C-007`.
- **Dependencies:** none (or earlier feature IDs).
- **Estimated worker budget:** Sonnet, ~80k input.
- **User-observable behavior?** yes/no (decides whether User-Testing Validator runs).

### F002 — <slug>

(same shape)

…

## Parallel exploration plan (planning phase)

Before features start, the Orchestrator fans out Explorer subagents on questions the plan depends on:

- E1: ...
- E2: ...
- E3: ...

(Explorers run during planning only. Once features start, only Validators may parallelise — and only against the same feature.)

## Risks & mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| ... | low/med/high | low/med/high | ... |

## Approval

- [ ] Plan reviewed and approved by user
- Approved at: `<ISO timestamp>`
