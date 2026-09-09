# The wedge alarm

Configuration for away mode's escalation-delivery alarm. Behaviour and rationale live in [../protocols/afk.md](../protocols/afk.md).

## What it is for

An away-mode escalation that nobody acknowledges. The failure it defends against is **not** "nothing happened" — it is "something happened that needed you, and the message went nowhere."

## Settings

| Variable | Default | Meaning |
|---|---|---|
| `HARNESS_WEDGE_MINUTES` | `30` | How long an escalation may sit unacknowledged before the alarm starts |
| `HARNESS_WEDGE_REPEAT_MINUTES` | `10` | How often it repeats once alarming |
| `HARNESS_AFK_POLL` | `60` | Seconds between supervision passes |

## Delivery channels

`scripts/notify.sh` is the single owner of delivery, shared with the `Notification` hook so the two cannot drift apart. All channels are best-effort; a delivery failure never breaks the thing that was trying to send.

| Channel | Enabled by |
|---|---|
| macOS Notification Center | automatic on Darwin; urgent adds a sound |
| Slack | `HARNESS_SLACK_WEBHOOK_URL` |
| Email | `HARNESS_NOTIFY_EMAIL` (needs a working `mail(1)`) |
| stderr + terminal bell | always |

`HARNESS_NOTIFY_DRYRUN=1` prints what would be sent and sends nothing. The test suite uses it; it is also useful by hand when checking payload shaping.

## Setting it up

```sh
export HARNESS_SLACK_WEBHOOK_URL='https://hooks.slack.com/services/...'
export HARNESS_WEDGE_MINUTES=20
```

Put these in your shell profile, not in the repo — `config/` is gitignored local state and the harness never reads secrets from tracked files.

## Testing it end to end

Prove delivery **before** relying on it. An untested alarm is exactly the thing this feature exists to catch:

```sh
./scripts/afk.sh start 1h
./scripts/afk.sh daemon &
# force an escalation, then:
HARNESS_WEDGE_MINUTES=0 HARNESS_WEDGE_REPEAT_MINUTES=0 ./scripts/afk.sh tick
```

You should get an urgent notification. If you do not, fix that now — while you are watching.
