# Plan: 2026-05-22-add-marker

## Overview

A single feature: create `MARKER.md` at the repo root containing today's ISO date, committed via a conventional commit.

## Features (in serial execution order)

### F001 — add-marker

- **Goal:** Create `MARKER.md` containing today's ISO date.
- **Scope (files):** `/tmp/harness-test/MARKER.md` (new file).
- **Out of scope for this feature:** any other file; any second commit.
- **Contract assertions satisfied:** `C-001, C-002, C-003, C-004`.
- **Dependencies:** none.
- **Estimated worker budget:** Sonnet, ~5k input.
- **User-observable behavior?** no (no app to launch — Scrutiny Validator only, no User-Testing).

## Parallel exploration plan (planning phase)

None — the target repo is empty and the goal is unambiguous. The harness rules allow skipping Explorer fanout for trivial missions; this is one.

## Risks & mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Worker writes the wrong date format | low | low | Contract specifies `YYYY-MM-DD` exactly |
| Worker commits without conventional-commit prefix | low | low | Contract asserts `feat(add-marker):` prefix |
| Worker edits another file | low | medium | Contract asserts `git diff --name-only` yields only `MARKER.md` |

## Approval

- [x] Plan reviewed and approved by user (smoke-test pre-approval given in chat)
- Approved at: `2026-05-22T23:49:14Z`
