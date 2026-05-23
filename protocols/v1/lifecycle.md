# Protocol: Mission Lifecycle

The state machine every mission moves through. The Orchestrator owns transitions; the filesystem records them.

## States

| State | Entered when | Exit transitions |
|-------|--------------|------------------|
| `intake` | Orchestrator scaffolds the mission folder via [/mission-start](../.claude/skills/mission-start/SKILL.md) | → `planning` |
| `planning` | Orchestrator starts reading the mission | → `contract` |
| `contract` | Plan exists | → `awaiting_approval` |
| `awaiting_approval` | Contract is drafted | → `executing` (user approves) or `intake` (user revises) |
| `executing` | Approved | → `feature_loop` (entered as soon as first feature starts) |
| `feature_loop` | Per-feature work in progress | → `executing` (between features) → `closing` (all features done) |
| `closing` | All features complete, integration check running | → `closed` or `abandoned` |
| `closed` | Final integration check green, post-mortem written | terminal |
| `abandoned` | Mission halted manually or by hard blocker | terminal |
| `paused` | Manual pause (long break, environment unavailable) | → `executing` |

`status.json` always records the current state, plus pointers (`current_feature`, `last_handoff`, etc.). See [templates/status-schema.md](../templates/status-schema.md).

## Transitions in detail

### intake → planning
- The Orchestrator reads `mission.md`, the user-supplied intent.
- Reads any `learnings/patterns/` entries relevant to the goal.
- Resolves relative dates to absolute dates.

### planning → contract
- `plan.md` lists features `001`, `002`, … in serial order.
- Each feature has a slug, a one-line summary, an estimated scope, and a list of contract assertion IDs it satisfies.

### contract → awaiting_approval
- `contract.md` complete. Assertions are executable or behavioral.
- Each assertion has an ID (`C-001`, `C-002`, …) so features can cite them.

### awaiting_approval → executing
- User says "approved" (or equivalent). The Orchestrator records the approval in `log.md` with a timestamp.

### executing → feature_loop (and back)
- For each feature, the Orchestrator runs the sub-state machine in [worker.md](worker.md), [scrutiny-validator.md](scrutiny-validator.md), [user-testing-validator.md](user-testing-validator.md).
- On feature complete-green, advance.
- On feature red, open a follow-up feature (numbered after the current feature, with `-followup-<n>` suffix), and continue.

### executing → closing
- All features in `plan.md` have a green status, including any follow-ups.

### closing → closed
- Full contract executed end-to-end as integration check. Green.
- `post-mortem.md` written.
- At least one entry added to `learnings/patterns/` or `learnings/anti-patterns/`.

### any → abandoned
- Hard blocker the Orchestrator cannot resolve. Recorded with `abandoned_reason`.

### any → paused
- Manual pause. Resumes by setting state back to `executing`.

## Approval gates

The only mandatory human gate is `awaiting_approval → executing`. Anything else, the Orchestrator decides.

Optional checkpoints (off by default, enable via `status.json.checkpoints`):
- Pause for human review after every N features.
- Pause if any feature requires >K follow-ups (suggests contract defect).
- Pause if validators trip on the same assertion across two features (suggests systemic issue).

## Resumability

Any new Claude session reads `status.json` + the last entry in `log.md` and can pick up. See [/mission-resume](../.claude/skills/mission-resume/SKILL.md). The `SessionStart` hook also injects active-mission context automatically.
