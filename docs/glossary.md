# Glossary

## Approval gate

The single mandatory human checkpoint in the mission lifecycle. The Orchestrator presents the completed plan and validation contract to the user and waits for explicit approval before spawning any Worker. After approval, the Orchestrator runs the feature loop uninterrupted unless a genuine blocker arises.

## Chain

A sequence of follow-up features produced when a Validator returns red. Each follow-up's acceptance criteria are the failing assertions from the previous verdict. A chain ends when Scrutiny returns green on the latest feature in the sequence.

## Contract

Short for "validation contract." The single source of truth for whether a mission is done. Written by the Orchestrator before any Worker is spawned. Contains executable assertions (commands + expected exit codes, file invariants, observable behaviors) — not aspirations. Lives at `missions/<id>/contract.md`.

## Explorer

A read-only subagent spawned in parallel during the planning phase to map the codebase, read docs, or fetch external sources. Explorers have no Write or Edit tools. Multiple explorers may run concurrently; non-explorer subagents may not. Defined in `.claude/agents/explorer.md`.

## Feature

One unit of work in a mission plan. Features are ordered so that earlier ones do not depend on later ones. Each feature has a spec (`features/<n>-<slug>/spec.md`), a handoff (`handoff.md`), scrutiny verdict (`scrutiny.md`), user-test verdict (`user-test.md`), and a status file. One Worker per feature.

## Feature loop

The iterative section of the mission lifecycle that processes features one at a time: spawn Worker → receive handoff → spawn Scrutiny Validator → spawn User-Testing Validator (if applicable) → decide pass or follow-up.

## Follow-up feature

A new feature opened by the Orchestrator when a Validator returns red. It inherits the failing assertions as its acceptance criteria. The original feature is never patched in place — the follow-up is the fix. This keeps the audit trail intact.

## Handoff

The structured report a Worker returns after completing a feature. Must begin with `## Feature:` and contain: what was implemented, what was left undone, commands run with exit codes, issues discovered, and whether specified procedures were followed. Persisted at `features/<n>/handoff.md`.

## Mission

A goal that has been accepted into the harness lifecycle, decomposed into features, and assigned a validation contract. Missions live under `missions/<YYYY-MM-DD-slug>/`. They progress through states: `intake` → `planning` → `awaiting_approval` → `executing` → `closed` (or `paused` / `abandoned`).

## Orchestrator

The main Claude Code session. Reads the mission spec, decomposes into features, writes the validation contract, waits at the approval gate, then drives the feature loop by spawning Workers and Validators. Never implements features directly. Defined in `.claude/agents/orchestrator.md` and activated via `.claude/settings.json`.

## Recursive mission

A mission that spawns a sub-mission as one of its features. The sub-mission must use its own isolated `missions/<sub-id>/` folder and must not mutate the parent mission's state files. See `learnings/anti-patterns/recursive-mission-stability-guards.md`.

## Scout

A long-lived subagent (introduced in v0.4) that accumulates knowledge across missions. Unlike Workers and Validators (which are fresh-per-spawn by design), the Scout uses persistent memory to build a cross-mission knowledge base. Defined in `.claude/agents/scout.md`.

## Scrutiny Validator

An adversarial subagent that verifies a feature against the validation contract. Sees the contract slice and the diff only — never the Worker's handoff or reasoning. Runs every assertion, looks for hardcoded secrets and swallowed errors, and returns a verdict that begins with `## Feature:`. Default model: Haiku. Defined in `.claude/agents/scrutiny-validator.md`.

## Serial execution

The rule that Workers run one at a time. Each Worker inherits the codebase via git from the previous Worker's commit. Enforced by the `pre-agent-spawn-serial.sh` hook, which blocks concurrent non-explorer spawns.

## User-Testing Validator

A subagent that exercises user-observable behavior after Scrutiny passes. Launches the app, runs flows as a QA engineer would (Playwright, computer-use, manual smoke), and returns a verdict. Spawned only when the feature has user-facing behavior. Default model: Sonnet. Defined in `.claude/agents/user-testing-validator.md`.

## Validation

The phase after a Worker handoff where one or two Validators independently verify the feature against the contract. Validation is adversarial — Validators are fresh spawns with no knowledge of the implementation reasoning.

## Verdict

The structured output of a Validator. Must begin with `## Feature:`, contain an assertion table, adversarial findings, and (if red) follow-up specs. Any text outside this structure is a protocol violation.

## Worker

A short-lived subagent spawned by the Orchestrator to implement exactly one feature. Receives a feature spec, the relevant contract slice, and the previous feature's handoff (if any). Commits via a single conventional commit and returns a structured handoff. Workers have fresh context every spawn — they do not accumulate state across features. Defined in `.claude/agents/worker.md`.
