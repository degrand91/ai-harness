# Away mode — a real unattended run

Run 2026-09-09. Away mode's daemon loop, digest, escalation ladder and wedge
alarm had never been run for real; every test drove `tick` once by hand. This
is the loop running unattended to its deadline.

The clock is compressed, not faked — the real daemon, real ticks, real files:

```bash
afk.sh start 4m
HARNESS_NOTIFY_DRYRUN=1 HARNESS_AFK_POLL=5 \
HARNESS_WEDGE_MINUTES=1 HARNESS_WEDGE_REPEAT_MINUTES=1 afk.sh daemon
```

Scenario: one mission blocked on a decision, one crewmate whose ledger says
`failed`. Both should escalate; one is acknowledged mid-run and one is left to
wedge.

## What happened

| Time | Event |
|---|---|
| 20:13:57 | away mode on, until 20:17:57 |
| 20:13:57 | `ESCALATED hold-…`, `ESCALATED crew-T-DRILL-failed` — normal notification |
| 20:14:57 | both wedge-alarm at exactly the 1m threshold — **urgent** |
| ~20:15:10 | `afk.sh ack crew-T-DRILL-failed` |
| 20:15:58 | only the unacked hold alarms (2m) — acking really does stop it |
| 20:16:59 | hold alarms again (3m), on the configured repeat interval |
| 20:17:57 | daemon exits at its deadline, notifies "Away mode has expired" |

The ladder works. Thresholds fired on the second, the repeat interval held, an
event escalated once rather than every tick, and the acknowledged escalation
went quiet while the wedged one kept climbing.

## The defect this found

**At expiry, nothing supervises the fleet.**

The daemon stops at its deadline. The `state/.afk` marker survives until the
operator runs `afk.sh return`. Both the watcher (`scripts/watch.sh`) and the
Stop-hook re-arm tested that marker's bare presence to decide whether to stand
down — so in the gap between the deadline and the operator's return:

- the daemon is no longer ticking, so nothing escalates;
- the watcher is still stood down, so nothing wakes the session;
- the only signal was one expiry notification, which is precisely the
  "message goes nowhere" failure the wedge alarm exists to defend against.

The gap is unbounded. An 8h away mode that expires overnight leaves the fleet
unsupervised until morning, with a red feature or a blocking decision sitting
in a digest nobody is being told about.

`afk.sh status` also reported such a session as plainly "on", which is a lie
with consequences.

## The fix

`scripts/lib/afk-state.sh` now owns the question. `afk_in_force` is
marker-present AND within deadline, and that is what the watcher and the hook
ask — so the watcher takes back over the moment the daemon stops. An
unreadable marker counts as expired: of the two ways to be wrong, waking the
operator needlessly can be noticed, and silence cannot.

Verified against the expired drill home: `watch.sh --once` immediately reported
`crew T-DRILL failed`, which it had been silent about while the marker stood.

Regression cover: `tests/afk.test.sh`.
