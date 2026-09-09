---
name: afk
description: Enter away mode so the fleet runs unattended — routine events are batched into a digest, only captain-relevant events escalate, and an alarm fires if an escalation goes unacknowledged. Use when the captain says they are stepping away, or asks to be told only if something needs them.
argument-hint: [<duration> | return | status]
allowed-tools: Bash(./scripts/afk.sh *), Bash(./scripts/crew/reconcile.sh), Read
---

## Away mode

!`${CLAUDE_PROJECT_DIR}/scripts/afk.sh status`

---

`$ARGUMENTS` is a duration (`6h`, `90m`), or `return`, or `status`.

### Starting

```
./scripts/afk.sh start 6h
```

Then tell the captain to run the daemon in another terminal — it is the thing that actually watches:

```
./scripts/afk.sh daemon &
```

Say plainly what will and will not reach them:

- **Batched, not delivered:** a feature finishing, a validator passing, a crewmate reporting done.
- **Escalated:** a blocking decision, a red feature, a crewmate that failed or vanished, a stalled mission.
- **Alarmed:** any escalation still unacknowledged after `HARNESS_WEDGE_MINUTES` (default 30). This is the point of away mode — it defends against *an escalation going nowhere*, not against nothing happening.

While away mode is on, the Stop-hook watcher **stands down completely**. Two things deciding when to wake the session is two things disagreeing.

### Returning

```
./scripts/afk.sh return
```

Present the digest, then go straight to `/decide` if anything is blocking. Do not summarise the digest away — the captain wants to know what happened, including the routine parts they chose not to be interrupted for.

### Rules

- **Never acknowledge an escalation on the captain's behalf.** An ack means a human saw it; that is the whole signal.
- **Do not start away mode without saying how long.** An unbounded away mode is one the captain forgets is on.
- If away mode is already on, say so rather than restarting it — restarting resets the digest.
