# Protocol: Continuity

How the harness keeps going without being nudged, and — more importantly — how it is stopped from going when it should not.

---

## Two mechanisms, and which is primary

| | Mechanism | Role |
|---|---|---|
| **Primary** | The **turn-end guard** (`stop-no-red-status.sh`), a synchronous `Stop` hook | **Refuses** a stop that ends the loop for no reason |
| Backstop | The **watcher** (`stop-watch-rearm.sh` + `scripts/watch.sh`), an `asyncRewake` `Stop` hook | Parks on fleet state; wakes on real events, and on continuation only when the guard has failed open |

The ordering matters. Once crewmates are real processes, nearly every wake is an *event*: a ledger line, a PR going green, a stall. The remaining case — the orchestrator ended its turn with an obvious next step and nothing in flight — is an **orchestrator mistake**, and the right response is to refuse that stop, not to resume it forty-five seconds later on a timer.

## The blind-stop rule

The guard refuses when **all** of these hold:

- a mission is `executing`
- it has at least one `pending` feature
- no crewmate is in flight on it
- no **blocking** decision is open

It then tells the model its three legitimate options: dispatch, file the decision it actually needs, or `/pause`.

**Recency bound.** Only missions touched within `HARNESS_LOOP_ACTIVE_SECONDS` (24h) count. This was not in the original design — it was found by pointing the finished guard at this repo, where two real missions had sat `executing` with pending features for **105 days**. Without the bound they would have refused every stop in every future session. A rail that fires forever on work nobody is doing is a rail people switch off, which costs more than the rail was worth. The same bound applies to the `awaiting_approval` rule and to the watcher's continuation wake.

**Loop safety:** three consecutive refusals and it fails open with one notification. A guard that can refuse forever is a wedged session, and a wedged session is worse than a loop that ran one feature too many. The counter resets the moment the loop is no longer blind.

## The watcher

Registered as a second `Stop` hook with `"asyncRewake": true` and an 8-hour timeout. Claude fires it in the background; it parks on a poll loop and, on an actionable event, prints to **stderr** and exits **2**, which Claude delivers as *Stop hook feedback* — waking an idle session. Zero tokens while parked.

It runs in the **foreground** of the hook's own process tree (never `&`), so Claude's timeout or teardown kills the watcher with the hook.

### What it wakes for, in priority order

1. A crewmate reached `done`, `failed`, or `blocked`
2. A live crewmate has been silent past `HARNESS_STALL_SECONDS` (1200)
3. The loop has an agent-owned next action — after a grace period, and only as a backstop

### What it never wakes for

- **A blocking decision is open.** The captain owns it; waking to do more work is the wrong move.
- **The mission is `paused`.** The captain took the wheel.
- **Away mode is active.** The AFK daemon owns the watcher — two things deciding when to wake is two things disagreeing.
- **`state/.watch-off` exists.** The kill switch.

### Rails

| Rail | Behaviour |
|---|---|
| Scope | Both markers checked on the **data** root. Checking the code root would always pass, so the hook would arm anywhere a `missions/` folder happened to exist. |
| Identity | Only the session owning `state/session.lock` may arm. A second session never wakes anything. |
| Single-flight | One watcher per home; a live owner means stand down. |
| Continuation cap | `HARNESS_MAX_AUTO_CONTINUE` (10) consecutive continuation wakes, then one notification and silence. Event wakes are **not** capped. |
| Reset | `UserPromptSubmit` clears the epoch. A real message from the captain means the loop is attended again. |
| Absolute cap | `HARNESS_MAX_PARK` (28800s). |
| Recency | Only missions touched within `HARNESS_LOOP_ACTIVE_SECONDS` (86400s) can trigger a continuation wake. |

## Pause is a recorded state, not a mood

"Stop, I'll take over" ends a turn. Without a recorded pause the guard would refuse that stop and the backstop would resume the loop — the harness arguing with the captain about whether it is finished.

`/pause` writes `state: paused`. Both the guard and the watcher check it. `/resume` puts it back, after checking for unanswered decisions that would only stop it again.

## Away mode

`/afk` hands supervision to `scripts/afk.sh daemon`. Routine events are batched into a digest; only captain-relevant ones escalate. See [afk.md](afk.md) and [../docs/wedge-alarm.md](../docs/wedge-alarm.md).
