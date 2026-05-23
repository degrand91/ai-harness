# Changelog

All notable changes to the harness are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/), and the harness adheres loosely to [Semantic Versioning](https://semver.org/).

## [0.3.0] — 2026-05-23

### Added
- `protocols/multi-provider-validation.md` — design for the Multi-provider Scrutiny Validator pattern: env var `HARNESS_EXTERNAL_VALIDATOR_PROVIDER`, two-agent-file routing, Haiku fallback semantics.
- `.claude/agents/scrutiny-validator-external.md` — sibling agent with `mcpServers:` frontmatter scaffold; ships configured but un-exercised on machines without an external provider CLI.
- Per-role × per-provider cost columns in `templates/post-mortem.md` and an optional `provider` field in `templates/status-schema.md`.
- Orchestrator-side defensive verdict-parsing rule documented in `.claude/agents/orchestrator.md` (resolves the recurring `validator-prose-preamble` anti-pattern from missions `2026-05-22-add-marker` and `2026-05-23-add-marker2`).

### Changed
- `protocols/model-routing.md`: section heading `Provider isolation (v0.5)` → `Provider isolation (v0.3)`, with cross-reference to the new protocol doc.
- `CLAUDE.md` and `.claude/agents/orchestrator.md`: document the env-var-driven scrutiny-spawn routing rule.
- `learnings/proposals/tighten-validator-role-prompt.md` flipped from `status: open` → `status: accepted` with implementation reference.

### Known gaps
- The positive multi-provider path (orchestrator spawns `scrutiny-validator-external`, MCP server connects to a non-Claude provider, Scrutiny runs) is **documented but un-exercised in this release** — no external provider CLI is installed on the development machine. Operators with a configured provider should treat v0.3 as a contract for behaviour, not as a tested end-to-end path. Tracked as v0.3.1 follow-up.
