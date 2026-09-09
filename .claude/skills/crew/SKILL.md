---
name: crew
description: Inspect, steer, or stand down the crewmates working in their own worktrees. Use to see what a crewmate is doing, to redirect one mid-task, to rescue one that reported blocked, or to land finished work.
argument-hint: [list | peek <task> | send <task> "<text>" | attach <task> | teardown <task>]
allowed-tools: Bash(./scripts/crew/*), Bash(./scripts/pr-poll.sh *), Read
---

## The crew

!`${CLAUDE_PROJECT_DIR}/scripts/crew/reconcile.sh`

---

`$ARGUMENTS` says what the captain wants. With no arguments, summarise the above
and stop.

### Reading the reconcile output

It is **ledger first, process second** — a crewmate's own account of itself
outranks whether its process happens to still be running.

| Line | What to do |
|---|---|
| `working` | Nothing. Do not interrupt to check on it. |
| `done` | Run the validators against its worktree, then tear down on green. |
| `blocked` | It needs a decision. **File it** (`/decide` → `hold.sh open`), get an answer, then `send` the answer. Attach only if the situation is not expressible as a steer. |
| `failed` | Read the handoff. Re-brief, or tear down with `--abandon`. |
| `SUSPICIOUS` | The process vanished without claiming an outcome. `peek` it, look at the worktree, then decide. **Never assume it failed** — the worktree may hold real work. |

### Steering

```
./scripts/crew/send.sh <task> "<message>"
```

The steer is written to disk before any signal, so it survives even if the
runner is not listening. `run.sh` interrupts the crewmate and resumes it with
your message. Use this rather than `attach` whenever the correction can be said
in a sentence.

### Attaching

`./scripts/crew/attach.sh <task>` resumes the crewmate's *own* session
interactively, in its worktree. Only possible once it has stopped, and it is the
captain's hands on the keyboard, not yours. Afterwards, re-brief from the
handoff — you cannot see what they typed.

### Rules

- **A crewmate cannot reach the captain.** If it is blocked, the decision is
  yours to file and the captain's to answer. Do not relay a question by leaving
  it in chat.
- **Do not tear down anything that has not reported `done`**, except deliberately
  with `--abandon`. `blocked` is waiting, not finished.
- **Do not raise `crew.max_concurrent`** to make things go faster.
  [serial-execution.md](../../../protocols/serial-execution.md) explains why it is 1.
- **Peek is bounded** for a reason. Do not cat a whole window log into context.

Full lifecycle: [protocols/crew.md](../../../protocols/crew.md).
