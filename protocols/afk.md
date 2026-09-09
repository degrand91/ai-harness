# Protocol: Away Mode

`/afk` lets the fleet run while the captain is not watching, without either spamming them or losing something that needed them.

---

## The three tiers

| Tier | Examples | What happens |
|---|---|---|
| **Routine** | a feature closed green, a validator passed, a crewmate reported `done` | Digest line. No delivery. |
| **Captain-relevant** | a blocking decision, a red feature, a crewmate that failed or vanished, a stalled mission | Escalation: delivered, and an ack file is written |
| **Wedged** | any escalation still unacknowledged after the threshold | The alarm climbs until acked or away mode ends |

## The wedge alarm is the point

It does not defend against *nothing happening*. It defends against **something happening that needed you, and the message going nowhere** — a notification suppressed, a webhook misconfigured, a laptop asleep.

Every escalation writes `state/afk-escalations/<id>.json` with `acked_at: null`. If nothing acknowledges it within `HARNESS_WEDGE_MINUTES` (default 30), the alarm fires and repeats every `HARNESS_WEDGE_REPEAT_MINUTES` (default 10) at urgent level, which adds a sound and a terminal bell on top of the ordinary channels.

**Only a human acknowledges.** An ack means someone saw it; that is the entire signal. The orchestrator must never ack on the captain's behalf.

## Away mode owns the watcher

While `state/.afk` exists the Stop-hook watcher stands down completely. Two things deciding when to wake the session is two things disagreeing.

## Commands

```sh
./scripts/afk.sh start 6h     # enter; writes state/.afk and resets the digest
./scripts/afk.sh daemon &     # the supervision loop — this is what actually watches
./scripts/afk.sh status       # on/off, and how many escalations are unacknowledged
./scripts/afk.sh ack <id>     # a human saw it
./scripts/afk.sh return       # digest + unacknowledged list, and hand back to the watcher
```

## Rules

1. **Always bounded.** An unbounded away mode is one the captain forgets is on.
2. **Escalate once per event.** The alarm owns repetition; ticking must not re-raise.
3. **Never ack for the captain.**
4. **The digest is a full history**, including routine events. On `return`, present it — the captain chose not to be interrupted, not to be kept ignorant.
5. **Restarting resets the digest**, so say away mode is already on rather than restarting it.
