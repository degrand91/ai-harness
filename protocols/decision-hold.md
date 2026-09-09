# Protocol: Decision Holds

**A blocking question to the captain is not asked until it is filed.**

---

## Why

A question asked in a chat turn lives only in that turn. A restart erases it. A context compaction summarises it away. Either way the captain is asked the same thing twice — and that is how they stop trusting the queue and go back to watching terminals themselves.

The captain had already worked this out by hand: `open_questions` and `user_actions` with `status: "decided-pending-user"`, maintained by hand in one mission's `status.json`. This makes it a schema the tooling reads.

## The mechanism

One file per decision under `missions/<id>/decisions/`. Answering **moves** it to `decisions/answered/`. See [templates/decision-hold.md](../templates/decision-hold.md) for the schema.

```sh
./scripts/hold.sh open <mission> --question "..." [--options "a,b"] [--recommend "..."] [--advisory]
./scripts/hold.sh list
./scripts/hold.sh answer <mission> <id> "<answer>"
./scripts/hold.sh show <mission> <id>
```

## Where it is enforced

| Point | Behaviour |
|---|---|
| **SessionStart** | Open decisions are injected **first**, ahead of inbox notes and mission state. They are questions already asked and not answered; presenting work before them is how a session does something the captain was about to redirect. |
| **PreCompact** | Open decisions are written to `state/precompact-<session>.md`, and the next prompt re-injects them once. Compaction is the second way an answer is lost, after a restart. |
| **Stop guard** | A mission in `awaiting_approval` with **no** decision filed blocks the stop. The question exists only in a chat turn; refuse rather than let it evaporate. |
| **Snapshot / `/fleet`** | Open decisions appear per mission, so a blocked mission is visibly blocked on the captain rather than on work. |
| **Crew (Phase 3)** | A crewmate never asks the captain directly. It reports `blocked:` and the supervisor files the decision. |
| **Watcher (Phase 4)** | Never continuation-wakes while a blocking decision is open. The captain owns it; waking to do more work is the wrong move. |

## Rules

1. **File it, then ask it.** Not the other way round.
2. **Record the answer before acting on it.** An answer that exists only in the conversation is one restart from being lost.
3. **Silence is not a decision.** `hold.sh answer` refuses an empty answer.
4. **Never answer on the captain's behalf**, and never infer one from approval of something adjacent.
5. **One at a time.** Five decisions presented together get three answered vaguely.
6. **Moot is an answer, not a deletion.** Close it with the reason recorded.
7. **Advisory holds do not block.** They are visible; nothing waits on them.
8. **An unreadable hold counts as blocking.** We cannot prove it is safe to pass.

## Mission approval is DH-000

`awaiting_approval` stops being a special case. `/mission-start` files `DH-000` — *"approve this plan and contract?"* — and approval is its answer. One mechanism, one skill, one place to look.
