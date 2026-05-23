---
name: log
description: Append a timestamped line to the current mission's log.md. Use for state transitions and notable events. Cheap. Idempotent against duplicates is NOT guaranteed — write one line per real event.
argument-hint: <message>
allowed-tools: Bash(date *), Bash(printf *), Bash(ls *), Bash(jq *), Read
---

## Current UTC timestamp
!`date -u +%Y-%m-%dT%H:%M:%SZ`

## Most recent mission id
!`ls -t ${CLAUDE_PROJECT_DIR}/missions 2>/dev/null | grep -v '^\\.gitkeep$' | head -n1 || echo "(none)"`

## Message
$ARGUMENTS

---

Append a single line to the most recent mission's `log.md` in this exact format:

```
[<UTC timestamp>] $ARGUMENTS
```

Use the Bash `printf '%s\n' "[<ts>] <msg>" >> missions/<id>/log.md` pattern (single-quoted format, double-quoted line, properly escaped).

If `$ARGUMENTS` is empty, ask the caller for a message — don't append empty entries.

If there is no current mission, surface that and exit. Do not create one — that's `/mission-start`'s job.

## Anti-patterns

- ❌ Appending without a timestamp.
- ❌ Multi-line entries. One line, one event.
- ❌ Writing the same event twice. Hooks may also append; coordinate by being terse and intentional.
