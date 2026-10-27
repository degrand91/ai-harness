---
name: ponytail
description: The harness's implementation discipline — solve the whole problem with the least new code. Use when writing or changing code: pick the smallest change that fully works, reuse what exists before adding, and never add a dependency or abstraction nobody asked for. The operative copy lives in .claude/agents/worker.md because workers can't load skills; this is the canonical reference.
disable-model-invocation: true
argument-hint: lite | full | ultra
allowed-tools: Read, Grep, Glob
---

# ponytail

The best code is the code never written. Solve the whole problem with the least
new code. This is the harness's **implementation discipline** — it governs the
Worker (baked into [worker.md](../../agents/worker.md), since workers run with
`omitClaudeMd: true` and can't load this file) and shapes how the Orchestrator
sizes features and chooses lanes ([fast-path.md](../../../protocols/fast-path.md)).

It cuts **code volume**; the fast-path lanes cut **ceremony**. They compose.

## Before you write

Read the task and the code it touches. List every place the change must reach:
callers, tests, fixtures, config, exports. Check what it could break: data it
would destroy or expose, callers that stop working. That is scope. Extra features
are not.

## The smallest complete change

Take the first option that fully works:

1. **Does it need to exist?** Skip features, options and flexibility nobody asked
   for, and name them in one line. A vague request gets the smallest version that
   does the core job.
2. **Already in this codebase** (a helper, component, pattern)? Use it the way the
   surrounding code does.
3. **Standard library / platform feature?** Use it, unless the project has its
   own. A house component beats a native widget.
4. **An installed dependency?** Use it. Never add a dependency for a few lines.
5. **One line a reader gets at a glance?** One line.
6. Otherwise: the minimum code that works.

## Rules

- Be lazy about the solution, **never** about the change itself: finish every
  part the task needs — the callers, tests and fixtures your change breaks.
- No abstraction, wrapper, option, config, boilerplate or "for later" code nobody
  asked for. Deletion beats addition. Keep the codebase's existing structure,
  layers and conventions.
- The shortest working diff wins, once you know everything it must touch. A
  one-liner that needs decoding is not short.
- Comment only the *why* the code can't show, in one line.
- Bug fix: grep every caller of the function you touch, then fix the root cause
  once in the shared code.
- Code you move or merge keeps its error handling and validation.
- Between options of equal size, take the one correct on edge cases.
- New non-trivial logic (a branch, loop, parser, money/security, or a whole new
  script) leaves one small test or an assert-based self-check. Trivial changes
  need none.
- A shortcut with a known limit gets a comment: `shortcut: <the limit>, <when to
  upgrade>`.

## Never cut

Validation at trust boundaries, error handling that prevents data loss, security,
accessibility, calibration real hardware needs, anything the user asked for.
These override "lazy" every time — and they align with the harness's
always-validate floor ([fast-path.md §3](../../../protocols/fast-path.md)).

## Levels

| Level | Behavior |
|-------|----------|
| **full** | The rules above. Default. |

`lite` and `ultra` are reserved; until defined they behave as `full`.
