---
name: inbox
description: Capture an idea without interrupting work, or present and acknowledge notes captured earlier. Use when the captain raises something mid-task that should not derail the current mission, or when undrained notes are waiting at session start.
argument-hint: [note <text> | drain | status]
allowed-tools: Bash(./scripts/inbox.sh *), Read
---

## Pending notes

!`${CLAUDE_PROJECT_DIR}/scripts/inbox.sh list`

---

`$ARGUMENTS` says which of four different jobs this is. They look like one job and are not — keep them apart.

| Verb | What it is for |
|---|---|
| `note` | The captain raised something while you were mid-task. File it, say you filed it, and **carry on with what you were doing.** Do not start on it. |
| `drain` | Present the pending notes so the captain can decide. Acknowledge only what they actually resolve: `./scripts/inbox.sh drain --ack N001 N002`. |
| `status` | One line, from durable records only. Reads nothing else and writes nothing — safe to run any time. |
| `ask` | A side question the captain wants answered, that must **not** become fleet work. One-shot, no tools, no record. |

Rules:

- **A note is not a task.** Filing it is the whole action. Turning a note into a mission requires the captain to say so.
- **Never acknowledge on the captain's behalf.** An acknowledged note is archived and stops being surfaced; do it only for notes they explicitly resolved.
- A note is presented at session start until acknowledged, so nothing is lost to a crash or a compaction.
