# Dry-run: try the harness without shipping anything

Use this to sanity-check the protocol against a no-op mission before running it against real code.

## Scenario

A mission whose only goal is to add a `MARKER.md` file containing the current date.

## Steps

1. Pick a throwaway repo (init a fresh git repo if needed).

2. Open a Claude Code session at the harness folder. Tell Claude:
   > Start a mission: "Add MARKER.md with today's date". Target repo: `<path-to-throwaway-repo>`.

3. Watch Claude:
   - Scaffold `missions/<id>/` inline (mission.md, plan.md, contract.md, status.json, log.md).
   - Author `mission.md` from your prompt using `templates/mission-spec.md`.
   - Possibly fan out a couple of Explorer subagents (it should skip if obviously unnecessary).
   - Author a `plan.md` with one feature: `001-add-marker`.
   - Author a `contract.md` with minimal but real assertions:
     - File `MARKER.md` exists at the repo root after the feature.
     - File contains a valid ISO date.
     - `git log -1 --pretty=%s` matches `feat(add-marker): ...`.
   - Wait for your approval.

4. Approve. Watch Claude:
   - Spawn a Worker. Worker creates `MARKER.md`, commits, returns a handoff.
   - Spawn a Scrutiny Validator. Validator confirms the three assertions. Verdict green.
   - Mark feature done. Integration check green.
   - Write `post-mortem.md`. Write a one-line `learnings/patterns/<slug>.md`.

5. Inspect the artifacts:
   ```bash
   ./scripts/status.sh
   tree missions/<the-id>
   ```

## What this teaches

- The plumbing works end-to-end.
- The Orchestrator obeys the protocol on a trivial goal (it should not skip the contract or the approval gate just because the work is small).
- You see a real `post-mortem.md` and a real `learnings/` entry get created.

## Common surprises on first run

- The Orchestrator may want to skip Explorer fanout. Fine for a trivial mission — but watch that it stays disciplined as missions grow.
- The Orchestrator may try to add a "User-Testing Validator" for a non-user-facing feature. Tell it: this is non-user-facing.
- The Scrutiny Validator may report `skipped` on a malformed assertion. That's not a failure of the harness — that's the Validator working as designed. Fix the contract.
