# Protocol: Remote Trigger

> **Status: PARTLY SUPERSEDED.**
>
> Escalation policy now lives in [afk.md](afk.md) and delivery in `scripts/notify.sh`.
> What is still current here: the *reasoning* about when to surface to the operator
> versus continue. What is not: the trigger mechanics, which the watcher owns
> ([continuity.md](continuity.md)).

Define exactly when the Orchestrator surfaces to the user (fires a notification) versus continues autonomously. Surfacing is a high-cost event — it breaks the operator's attention. This protocol keeps surfacing rare and intentional.

---

## Purpose

In headless and background mode the Orchestrator drives the full mission lifecycle — intake, plan, feature loop, close — without human involvement. The `notify-at-gate.sh` hook is the delivery wire; this protocol specifies which events justify pulling that wire.

The guiding principle: **surface only when the Orchestrator genuinely cannot proceed without human input, or when the mission has reached a meaningful terminus the operator asked to be told about.**

---

## Mandatory surface triggers

The following events MUST fire the notification hook regardless of whether blanket pre-approval is active.

### 1. Approval gate reached (without blanket pre-approval)

The Orchestrator has written `plan.md` and `contract.md` and is waiting for the operator to sign off before spawning any Workers.

**Exception:** If the session prompt contains explicit blanket pre-approval language (see `feedback-blanket-approval` memory), the gate is skipped and no notification is sent. The blanket-approval message is recorded in `log.md` as the approval artifact instead.

### 2. Mission closed with green status

The final contract check has passed and the mission `status.json` is `"state": "closed", "health": "green"`. This is the expected terminus — tell the operator their goal shipped.

For chained missions (blanket approval active), surface only at the chain terminus (the final version milestone) unless the operator explicitly asked for per-mission summaries.

### 3. Unresolvable red status (two consecutive follow-up failures on the same feature)

If a feature has failed scrutiny twice in a row on the same assertion, the contract may be defective or the problem space may genuinely require human direction. The Orchestrator MUST surface at this point, not attempt a third follow-up autonomously.

Surface message MUST include:
- Feature slug and assertion IDs that are still failing.
- A brief statement of what the Orchestrator tried.
- A proposed next step (contract amendment, scope reduction, or explicit decision request).

### 4. Genuine environmental blocker

Conditions the Orchestrator cannot work around by itself:

- Missing or expired credentials (`ANTHROPIC_API_KEY`, external validator API key, etc.).
- Working directory is unreadable or the git tree is in a detached/conflicted state the Orchestrator cannot repair.
- A required tool or binary is absent from `PATH`.
- A network dependency is unreachable and there is no offline fallback.

Surface immediately on detection. Do not attempt retries beyond a single re-check.

---

## Optional / configurable surface triggers

The following events MAY fire the notification hook. They are off by default and intended for long-running or high-stakes missions where intermediate visibility has value.

### Every N closed features

Set `HARNESS_NOTIFY_EVERY_N_FEATURES=<n>` in the environment. When the n-th, 2n-th, … feature closes green, send a progress ping: mission id, features closed so far, features remaining.

Default: unset (no periodic pings).

### Validator anti-pattern recurrence

If the same structural anti-pattern (e.g., validator-prose-preamble, swallowed-error-in-production-path) appears in three or more consecutive scrutiny reports across different features, the Orchestrator MAY surface a heads-up. This signals a systemic issue in the codebase rather than an isolated slip.

The threshold is three occurrences. Below that, the Orchestrator handles it with follow-up features as normal.

Default: disabled unless `HARNESS_NOTIFY_ANTIPATTERN_RECURRENCE=1` is set.

---

## Mechanism

1. The Orchestrator identifies a trigger condition.
2. It composes a notification payload:
   ```json
   {
     "hook_event_name": "Notification",
     "title": "<mission-id>: <trigger type>",
     "message": "<one or two sentences: what happened, what the operator should do>",
     "session_id": "<claude session id>"
   }
   ```
3. It invokes `.claude/hooks/notify-at-gate.sh` with the payload on stdin (the hook is wired in `settings.json` under `hooks.Notification`).
4. The hook delivers via the best available channel: macOS Notification Center, Slack webhook (`HARNESS_SLACK_WEBHOOK_URL`), or email (`HARNESS_NOTIFY_EMAIL`). It always exits 0 — notification failure never blocks the Orchestrator.
5. The trigger event is recorded in `log.md` with a `[SURFACE]` tag and an ISO-8601 timestamp.

---

## What NOT to surface

- Normal validator failures resolved by a follow-up feature (first or second attempt).
- Warnings that appear in build or test output but do not cause a failure.
- Slow-running features (duration is not a trigger).
- Decisions the Orchestrator is authorised to make autonomously (model selection, feature ordering, artifact format choices).
- The approval gate when blanket pre-approval is already in effect.

Unnecessary surfacing trains operators to ignore notifications. Treat the notification channel as a paging channel, not a status feed.

---

## Cross-references

- `feedback-blanket-approval` memory — `.claude/agent-memory/orchestrator/feedback_blanket_approval.md`
- Notification hook implementation — `.claude/hooks/notify-at-gate.sh` (F002)
- Headless invocation and auto-approval — `protocols/headless-mode.md`
- Mission lifecycle and approval gate — `protocols/lifecycle.md`
