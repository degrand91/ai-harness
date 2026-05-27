---
name: mission-status
description: Show the current state of a mission (most recent by default, or a specific id passed as argument). Read-only. Cheap. Use to answer "where are we?" before resuming.
argument-hint: [mission-id]
allowed-tools: Bash(cat *), Bash(ls *), Bash(./scripts/status.sh *), Read
---

## Live status

!`${CLAUDE_PROJECT_DIR}/scripts/status.sh $ARGUMENTS`

---

Summarise the above status for the user, in this shape:

```text
Mission: <id>
State:   <state> → <sub-state> (current: <F-id>, <feature state>)

Recent:
  F001 ... green  (0 followups)
  F002 ... green  (1 followup)
  F003 ... in_validation

Outstanding follow-ups: <listed or "none">
Spend so far: ~<N> tokens
Next action: <one line>
```

The "Next action" is **your** call, based on what the status shows:
- If a feature is `in_validation` and `scrutiny.verdict` is null → spawn the Scrutiny Validator subagent.
- If `scrutiny.verdict: green` and the feature is user-observable and `user_testing.verdict` is null → spawn the User-Testing Validator.
- If a feature is `closed` and there's a next feature pending → spawn its Worker.
- If all features closed and integration check not yet run → run the full `contract.md` end-to-end.
- If everything green and `post-mortem.md` not written → /mission-review.

Read-only skill. Do not write any files.
