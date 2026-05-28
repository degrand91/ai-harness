# Orchestrator Agent Memory — Template

> **Installation:** Copy this file to `.claude/agent-memory/orchestrator/MEMORY.md`
> after cloning or installing the harness.
>
> The `.claude/agent-memory/` directory is listed in `.gitignore`, so your memory
> stays local and is never committed to the repository. Each operator maintains
> their own independent memory.

## How to use this file

The Orchestrator reads this file at the start of every session via the `memory: project`
config in `.claude/settings.json`. Update it at the end of sessions or missions to
preserve context that would otherwise be lost between sessions.

Keep entries short. This file is loaded into every session's context — long entries
waste tokens. Use `learnings/patterns/` for curated, cross-mission knowledge instead.

---

## Session Context

_Notes about the current working environment: local paths, active services, credentials
locations, unusual setup details._

- Example: local dev server runs on port 4000, not the default 3000

## Active Mission

_What mission is currently in progress, where it stands, and what the next step is._

- Example: `2026-05-24-add-oauth` — approved, starting F003 (callback handler)

## Cross-Mission Patterns

_Recurring observations about how the harness behaves on this specific repo or
operator setup. Things that surprised you, worked well, or need watching._

- Example: Scrutiny validator consistently flags missing early-return guards — add to
  every contract slice

## Operator Preferences

_Preferences this operator has expressed that are not captured in protocols or rules._

- Example: prefers Haiku for all validators even when Sonnet is the default suggestion
- Example: always wants a dry-run mission before production harness runs

## Repository Facts

_Stable facts about this codebase that would otherwise require re-exploration each
session._

- Example: `missions/` directory grows large — `status.sh` is the cheap inspection path
- Example: hooks directory has post-tool-use, stop, session-start, subagent-stop handlers
