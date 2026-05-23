# Mission: Add MARKER.md with today's date

**ID:** `2026-05-22-add-marker`
**Started:** `2026-05-22T23:49:14Z`
**Author (user):** ``
**Repository:** `/tmp/harness-test`
**Branch:** existing default branch

## Goal (in the user's words)

> Add MARKER.md with today's date.

This is a smoke-test mission for the harness. Trivial goal, full protocol exercised.

## Why (motivation)

Validate end-to-end that the harness protocol runs unmodified on a no-op target — intake → plan → contract → approval gate → worker → validator → close.

## Non-goals

- Any application code changes beyond `MARKER.md`.
- Any second commit; one commit per feature is the rule.

## Constraints

- Repository is a fresh git repo with one empty commit (no test runner, no lint, no typecheck — contract must reflect this).
- Date format: ISO 8601 (`YYYY-MM-DD`).

## Inputs from the user

- Target repo path: `/tmp/harness-test` (created during smoke-test setup).

## Definition of "delivered"

`MARKER.md` exists at the repo root, contains today's ISO date, was added in a single conventional commit `feat(add-marker): ...`.

## Risks the user flagged

- None (smoke-test mission).

## Approval

- [x] Mission spec reviewed and approved by user (smoke-test pre-approval given in chat)
- Approved at: `2026-05-22T23:49:14Z`
