---
name: recursive-mission-stability-guards
description: When a mission edits the harness itself (recursive mission), every feature's contract slice must include guards that the still-in-use agent files (especially scrutiny-validator.md) remain parseable and byte-unmodified.
introduced_in_mission: 2026-05-23-ship-v0-3-multi-provider
tags: [contract, recursive-mission, validator, stability]
---

## Pattern

When the target repo of a mission **is** the harness itself, the contract must include at least two recursive-stability guards on every feature:

1. **Structural** — every `.claude/agents/*.md` file still parses (first line `---`, has matching `name:` field):
   ```bash
   for f in .claude/agents/*.md; do
     stem=$(basename "$f" .md)
     head -1 "$f" | grep -qE '^---$' || exit 1
     grep -qE "^name: ${stem}$" "$f" || exit 1
   done
   ```

2. **Behavioral / byte-identity** — the agent file in active use during this mission (typically `scrutiny-validator.md`, since it runs after every feature) is byte-unmodified from the start-of-mission state:
   ```bash
   diff <(git show <start-sha>:.claude/agents/scrutiny-validator.md) .claude/agents/scrutiny-validator.md
   # expected: no output, exit 0
   ```

Both assertions go in the per-feature contract slice. Workers see them; Scrutiny Validators verify them.

## Why

A recursive mission has a unique self-defeating failure mode: a Worker that breaks `.claude/agents/scrutiny-validator.md` (or its YAML frontmatter, or its filename pointer) makes the next feature's Scrutiny spawn fail — at which point the mission cannot validate any further work. The harness's "Stop hook blocks red status" rule means the session can't even close cleanly. Catching this at the contract gate is cheap; catching it after the fact requires reverting commits and re-running.

On `2026-05-23-ship-v0-3-multi-provider`, seven features touched `.claude/agents/`, `protocols/`, `templates/`, `CLAUDE.md`, and `learnings/`. Zero self-inflicted breakage. The guards never tripped — *because they existed in every feature spec, the workers knew to avoid the breakage in the first place*. That's the point: the guard's job is partly preventive, not just detective.

## How to apply

- **At contract authoring**: enumerate the agent files (and other infrastructure) the mission's own execution depends on. For every such file, write a structural assertion (parses) and a byte-identity assertion (unchanged unless explicitly in scope).
- **In every feature spec**, include those assertions in the contract slice — even if the feature has nothing to do with agent files. The point is that the Worker knows the guardrails and the Scrutiny Validator checks them.
- **If a feature legitimately needs to modify an agent file** (e.g., F004 in this mission edited `orchestrator.md`), the byte-identity assertion targets a *different* agent file (the one still in active use). The structural assertion still applies universally.
- **Sequence sensitively**: place agent-file edits later in the mission when possible, so earlier features' clean state is preserved as the inheritance baseline.

## Origin

`missions/2026-05-23-ship-v0-3-multi-provider/post-mortem.md`. v0.3 was the first mission to do substantial harness-on-harness work. Without these guards, F003 (adding a new agent file) or F004/F005 (editing `orchestrator.md`) could have silently broken the Scrutiny Validator used by every subsequent feature.
