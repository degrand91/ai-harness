# Scout Protocol

Scout is the harness's **cross-mission memory** agent. Unlike Explorer, which answers one focused question per spawn and is then discarded, Scout accumulates a durable understanding of the target codebase across every mission and surfaces that knowledge at intake time.

This document defines when to spawn Scout, what it returns, and how its memory file should be maintained.

---

## When to Spawn

Spawn Scout **at mission intake, before planning begins**, whenever you need orientation to the repository or want to surface recurring failure modes from prior missions.

The canonical trigger question is:

> "What do you remember about this target codebase that is relevant to the goal: `<goal>`?"

**Do not spawn Scout:**
- During the feature loop (use Explorer for narrow, per-planning questions)
- At mission close (Scout is intake-only)
- In parallel with other Scouts (Scout is a singleton — one at a time, sequentially)

---

## Memory File Location

Scout's persistent memory lives at:

```
.claude/agent-memory/scout/MEMORY.md
```

This file is read and updated on every Scout spawn. It accumulates dated entries across missions; older entries are never deleted unless explicitly superseded with a note explaining why. The Orchestrator must not write to this file directly — only Scout does.

---

## Relationship to Orchestrator MEMORY.md

The Orchestrator maintains its own memory at `.claude/agent-memory/orchestrator/MEMORY.md`. These two files serve different purposes:

| | Scout MEMORY.md | Orchestrator MEMORY.md |
|---|---|---|
| **Written by** | Scout agent | Orchestrator (you) |
| **Contents** | Durable codebase facts (architecture, team conventions, hotspot files, recurring failures) | Strategic context, mission-specific decisions, orchestration notes |
| **Lifespan** | Accumulates forever across all missions | May include mission-specific scratchpad notes |
| **Read by** | Scout at each spawn; Orchestrator reads the output summary | Orchestrator at session start |

The Orchestrator should read Scout's output summary (the structured findings report), not the raw memory file directly.

---

## Expected Output Format

Scout's reply must begin with `## Recall` and contain exactly four sections:

```markdown
## Recall
<Summary of what the memory file held before this spawn>

## Current findings
- <file or area> — <durable fact confirmed or newly discovered>

## Memory delta
- Added: <what was appended to memory>
- Removed / superseded: <what was removed, with reason>

## Caveats
- <bullet> (or "None")
```

The Orchestrator should treat `## Current findings` as the primary input to planning. The `## Memory delta` section confirms what was written back to the memory file.

---

## Memory Staleness

Scout writes only durable facts. However, facts can still go stale:

- **Architecture changes** — if a refactor mission reorganised layers significantly, prior structural facts may no longer be accurate.
- **Dependency updates** — specific line numbers and version strings are not written to memory for this reason.
- **Resolved failure modes** — if a recurring failure was fixed by a prior mission, Scout should mark it superseded in the delta, not leave it as a live warning.

When Scout returns findings that contradict what you know from the current mission context, trust the live codebase over the memory file and flag it as a caveat.

---

## Spawn Example

```text
Agent(
  subagent_type: "scout",
  model: "haiku",
  description: "Scout — intake for <mission-slug>",
  prompt: "What do you remember about this codebase relevant to: <goal>?"
)
```

Scout uses `memory: project` — it reads and updates `.claude/agent-memory/scout/MEMORY.md` automatically as part of its configured memory surface.
