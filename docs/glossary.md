# Glossary

## Anti-template gate

A design-quality sub-check run by the User-Testing Validator for any feature with `user-observable behavior: yes`. Activated in v0.8. The gate runs three harness-specific checks on top of the ECC global anti-template policy: screenshot evidence at 375/768/1440 px breakpoints (Gate 1), a negative test for stock-template indicators such as centered headline + gradient blob or uniform card grids (Gate 2), and verification that the feature spec declares a specific `style-direction:` field (Gate 3). A red anti-template gate makes the overall feature verdict red. Governed by `protocols/design-quality.md`; ECC global policy at `~/.claude/rules/ecc/web/design-quality.md` is authoritative.

## Approval gate

The single mandatory human checkpoint in the mission lifecycle. The Orchestrator presents the completed plan and validation contract to the user and waits for explicit approval before spawning any Worker. After approval, the Orchestrator runs the feature loop uninterrupted unless a genuine blocker arises.

## Checkpoint

A JSON snapshot written to `missions/<id>/checkpoint.json` that captures the mission's position in the feature loop: completed features, remaining features, the currently active feature, the last commit SHA, and the next concrete action for the Orchestrator. Schema fields: `mission_id`, `session_id`, `checkpoint_at` (ISO 8601), `mission_state`, `completed_features` (array), `remaining_features` (array), `current_feature` (string or null), `last_commit_sha`, `post_mortem_present` (boolean), `next_action` (string). Emitted after every feature close, at session-end, and every five completed features on long missions. Read by `/mission-resume` to reconstruct context in a fresh session without re-scanning `log.md`. Never edit by hand — regenerate via `scripts/mission-checkpoint.sh <mission-id>`. Governed by `protocols/checkpoint-protocol.md`.

## claude-plugin.json

Root-level Claude Code plugin manifest at the repository root. Best-effort implementation against an unpublished plugin spec — fields may need adjustment when Anthropic ships an official spec. Key fields: `name` (plugin identifier), `version` (semver), `description` (human-readable summary), `capabilities` (lists registered `agents`, `skills`, and `hooks`), `installation` (method and step-by-step instructions). Until `claude plugin install` support ships officially, the canonical install method is a manual copy of the `.claude/` directory into the target project.

## Contract

Short for "validation contract." The single source of truth for whether a mission is done. Written by the Orchestrator before any Worker is spawned. Contains executable assertions (commands + expected exit codes, file invariants, observable behaviors) — not aspirations. Lives at `missions/<id>/contract.md`.

## Explorer

A read-only subagent spawned in parallel during the planning phase to map the codebase, read docs, or fetch external sources. Explorers have no Write or Edit tools. Multiple explorers may run concurrently; non-explorer subagents may not. Defined in `.claude/agents/explorer.md`.

## /explore (skill)

A variadic-arg slash skill (`.claude/skills/explore/SKILL.md`) that fans out N concurrent Explorer subagents — one per question — and synthesises their findings into a single "Exploration brief". Accepts up to five questions per batch; additional questions are dispatched in sequential batches of five. Each Explorer receives exactly one narrow question and returns a four-section response (`## Question / ## Answer / ## Evidence / ## Caveats`). The skill collects all responses, discards raw output, and returns the merged brief to the Orchestrator. Governed by `protocols/parallel-exploration.md`.

## Feature

One unit of work in a mission plan. Features are ordered so that earlier ones do not depend on later ones. Each feature has a spec (`features/<n>-<slug>/spec.md`), a handoff (`handoff.md`), scrutiny verdict (`scrutiny.md`), user-test verdict (`user-test.md`), and a status file. One Worker per feature.

## Feature loop

The iterative section of the mission lifecycle that processes features one at a time: spawn Worker → receive handoff → spawn Scrutiny Validator → spawn User-Testing Validator (if applicable) → decide pass or follow-up.

## Follow-up chain

A sequence of follow-up features produced when a Validator returns red. Each follow-up's acceptance criteria are the failing assertions from the previous verdict. A chain ends when Scrutiny returns green on the latest feature in the sequence. Sometimes called simply "chain" — see also `Mission chain` for the cross-mission sense of the word.

## Follow-up feature

A new feature opened by the Orchestrator when a Validator returns red. It inherits the failing assertions as its acceptance criteria. The original feature is never patched in place — the follow-up is the fix. This keeps the audit trail intact.

## HARNESS_EXTERNAL_VALIDATOR_PROVIDER

Environment variable that controls which Scrutiny Validator variant the Orchestrator spawns at scrutiny-spawn time. When unset or empty, the Orchestrator routes to `scrutiny-validator` (default Haiku, no MCP). When set to any non-empty string, it routes to `scrutiny-validator-external` (external provider via MCP). The value is a free-form human-readable label (e.g. `"openai"`, `"gemini"`) — the harness tests only for presence, not the specific value. MCP credentials for the external provider belong in `.claude/agents/scrutiny-validator-external.md`, not in this variable. Governed by `protocols/multi-provider-validation.md`.

## Handoff

The structured report a Worker returns after completing a feature. Must begin with `## Feature:` and contain: what was implemented, what was left undone, commands run with exit codes, issues discovered, and whether specified procedures were followed. Persisted at `features/<n>/handoff.md`.

## Mission

A goal that has been accepted into the harness lifecycle, decomposed into features, and assigned a validation contract. Missions live under `missions/<YYYY-MM-DD-slug>/`. They progress through states: `intake` → `planning` → `awaiting_approval` → `executing` → `closed` (or `paused` / `abandoned`).

## Mission chain

A sequence of missions that collectively advance a roadmap target, where each mission's output is the starting state for the next. For example, a v0.3 mission may add multi-provider routing; a subsequent v0.4 mission adds the learning loop on top of that. Operators sometimes call both a follow-up-feature sequence and a mission sequence a "chain" — context disambiguates: a follow-up chain is intra-mission (one `missions/<id>/`); a mission chain spans multiple mission folders toward a larger goal. See also `Follow-up chain`.

## Orchestrator

The main Claude Code session. Reads the mission spec, decomposes into features, writes the validation contract, waits at the approval gate, then drives the feature loop by spawning Workers and Validators. Never implements features directly. Defined in `.claude/agents/orchestrator.md` and activated via `.claude/settings.json`.

## Recursive mission

A mission that spawns a sub-mission as one of its features. The sub-mission must use its own isolated `missions/<sub-id>/` folder and must not mutate the parent mission's state files. See `learnings/anti-patterns/recursive-mission-stability-guards.md`.

## Scout

A long-lived subagent (introduced in v0.4) that accumulates knowledge across missions. Unlike Workers and Validators (which are fresh-per-spawn by design), the Scout uses persistent memory to build a cross-mission knowledge base. Defined in `.claude/agents/scout.md`.

## scrutiny-validator-external

A sibling agent file to `scrutiny-validator`, defined in `.claude/agents/scrutiny-validator-external.md`. Carries the same role prompt, hard rules, and verdict format as the default Scrutiny Validator, but its YAML frontmatter includes a `mcpServers:` block that routes validation through a non-Claude provider via MCP. Activated when `HARNESS_EXTERNAL_VALIDATOR_PROVIDER` is set to a non-empty value; otherwise the Orchestrator falls back to the default `scrutiny-validator` (Haiku). The `mcpServers:` entries ship commented out — the operator uncomments and configures the relevant provider (e.g. OpenAI Codex, Gemini) before use. Governed by `protocols/multi-provider-validation.md`.

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
