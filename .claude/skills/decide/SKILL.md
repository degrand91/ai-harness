---
name: decide
description: Present open decisions awaiting the captain, one at a time in impact order, and record each answer to disk. Use when the captain asks what needs deciding, when a session starts with open decisions, or before starting new work while any decision is blocking.
argument-hint: [mission-id]
allowed-tools: Bash(./scripts/hold.sh *), Bash(./scripts/fleet.sh *), Read
---

## Open decisions

!`${CLAUDE_PROJECT_DIR}/scripts/hold.sh list`

---

Walk these **one at a time**, in the order *you* judge most consequential — not file order, and not oldest-first. A decision that blocks a mission outranks one that is advisory; a decision whose wrong answer is expensive to undo outranks one that is cheap to revisit.

For each, give the captain:

1. **The question**, in one sentence.
2. **What each option actually costs** — not a restatement of the options, but what changes if they pick each one.
3. **Your recommendation, and why.** You have read the code and they have not. A decision presented without a recommendation is work handed back.
4. Then stop and wait. One decision per turn.

When they answer:

```
./scripts/hold.sh answer <mission> <id> "<their answer>"
```

**Record it before you act on it.** An answer that exists only in the conversation is erased by a restart or a compaction, and the captain gets asked the same question twice — which is how they stop trusting the queue.

### Rules

- **Never answer on their behalf**, and never infer an answer from silence or from "sounds good" about something else.
- **Never batch.** Presenting five decisions at once gets three of them answered vaguely.
- If a decision has become moot, say so and propose closing it with the reason as the answer — do not delete it.
- If answering one decision changes another, say so before they answer the first.
- An `advisory` decision does not block work. Mention it, but do not stop for it.

### Filing a new one

```
./scripts/hold.sh open <mission> --question "..." [--options "a,b"] [--recommend "..."] [--context <path>] [--advisory]
```

A blocking question is not asked until it is filed. This includes mission approval, which is `DH-000` — see [protocols/decision-hold.md](../../../protocols/decision-hold.md).
