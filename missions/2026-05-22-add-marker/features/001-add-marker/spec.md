# Feature: F001 — add-marker

## Goal

Create `MARKER.md` at the root of `/tmp/harness-test` containing today's ISO date (`2026-05-22`) on a single line, committed via a conventional commit.

## Scope

Files this feature may touch:
- `/tmp/harness-test/MARKER.md` (new file)

Out of scope (do NOT edit, even if tempting):
- any other file in `/tmp/harness-test`
- the harness itself (`/Users/stefanodegrandis/projects/ai/harness/`)

## Contract slice

This feature is responsible for satisfying these assertions:

- **C-001 (executable):** `test -f /tmp/harness-test/MARKER.md` → exit 0.
- **C-002 (executable):** `[ "$(cat /tmp/harness-test/MARKER.md)" = "2026-05-22" ]` → exit 0.
- **C-003 (executable):** `cd /tmp/harness-test && git log -1 --pretty=%s | grep -qE '^feat\(add-marker\): '` → exit 0.
- **C-004 (executable):** `cd /tmp/harness-test && [ "$(git diff-tree --no-commit-id --name-only -r HEAD)" = "MARKER.md" ]` → exit 0.

## Procedures (report y/n in handoff)

- [ ] Created exactly one new file (`MARKER.md`).
- [ ] Made exactly one new git commit on top of the current HEAD.
- [ ] Commit message uses conventional format `feat(add-marker): <summary>`.
- [ ] Ran the contract slice assertions yourself before handing off; recorded each command and exit code.

## Inputs the Worker has

- This `spec.md`.
- The contract slice above.
- The target repo state at HEAD (`/tmp/harness-test`).

## Expected outputs

- One new file: `/tmp/harness-test/MARKER.md`.
- One new git commit in `/tmp/harness-test`.
- A handoff matching `templates/handoff-report.md`.

## User-observable behavior?

`no` — no app to launch. Scrutiny Validator runs; User-Testing Validator does not.

## Notes

- Today's date in UTC: `2026-05-22`. The file must contain exactly `2026-05-22` and nothing else (no trailing newline beyond the file terminator, no extra lines, no quotes).
- This is a smoke-test mission for the harness; the goal is to exercise protocol mechanics on a trivial target.
