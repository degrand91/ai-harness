# Command: mission-status

> Invoke when the user asks "where are we?" or before resuming an in-flight mission.

## What it does

Surfaces the current state of an active mission in human-readable form.

## Procedure

1. If the user names a mission id, use it. Otherwise pick the most recently modified folder under `missions/`.
2. Run:
   ```bash
   ./scripts/status.sh <mission-id>
   ```
   which renders `status.json` + the last 10 lines of `log.md`.
3. Surface, in this order:
   - Mission state.
   - Current feature (if any), its state, its color.
   - Last 3 feature outcomes.
   - Outstanding follow-ups.
   - Token & cost so far.
   - The next action the Orchestrator would take.

## Output format (to the user)

```text
Mission: 2026-05-23-add-oauth
State:   executing → feature_loop (current: F003 wire-login-button, in_validation)

Recent:
  F001 add-oauth-routes   green (0 follow-ups)
  F002 add-token-store    green (1 follow-up)
  F003 wire-login-button  in_validation

Outstanding follow-ups: none

Spend so far: 412k tokens (~$3.20)
Next action: spawn User-Testing Validator for F003
```

## What NOT to do

- ❌ Edit any files during a status check. Read-only.
- ❌ Re-spawn validators just to "verify." Trust the recorded verdicts unless the user asks for re-validation.
