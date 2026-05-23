# Changelog

All notable changes to the harness are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/), and the harness adheres loosely to [Semantic Versioning](https://semver.org/).

## [0.9.0] — 2026-05-23

### Added
- `protocols/headless-mode.md` — protocol for running the harness in fully headless / non-interactive mode via `claude --agent orchestrator -p "..."`. Documents the `--headless` flag semantics, environment variable overrides (`HARNESS_HEADLESS=1`), and how the Orchestrator detects it is running unattended and adjusts its gate behaviour accordingly.
- `notify-at-gate.sh` hook — `Notification` event hook that fires when the Orchestrator reaches the approval gate or mission close. Ships three delivery adapters: OS notification (`osascript` / `notify-send`), Slack webhook (`HARNESS_SLACK_WEBHOOK`), and email via `sendmail` (`HARNESS_NOTIFY_EMAIL`). Adapter selection is automatic based on which env vars are set; multiple adapters can be active simultaneously.
- `protocols/remote-trigger.md` — "wake me when the gate is reached" protocol. Documents the full unattended mission lifecycle: cron / CI schedules a headless run, Orchestrator progresses to the gate, `notify-at-gate.sh` pages the user, the user resumes the session and approves. Includes a reference wiring example for GitHub Actions and a macOS launchd plist.

### Known gaps
- Real overnight / cron deployment requires the operator to wire `notify-at-gate.sh` to their environment (set `HARNESS_SLACK_WEBHOOK` or `HARNESS_NOTIFY_EMAIL`, or rely on OS notifications). The harness ships the infrastructure; environment-specific wiring is the operator's responsibility.
- The literal exit criterion — "mission ran overnight unattended, paged the user at the gate, resumed in the morning" — is calendar-bound and cannot be demonstrated in-session. Infrastructure is complete and smoke-tested; the end-to-end overnight path is tracked as a v0.9.1 follow-up once a qualifying mission is scheduled.

## [0.8.0] — 2026-05-23

### Added
- `protocols/design-quality.md` — harness-level extension of the ECC web design-quality rules; defines the anti-template gate, banned patterns, required qualities checklist, and worthwhile style directions that the user-testing validator consults when evaluating UI-bearing features.
- Anti-template gate in `user-testing-validator` prompt — validator now explicitly checks "does this look like a default template?" and can reject a feature for taste/design-quality reasons, not just functional ones.
- `protocols/snapshots-convention.md` — convention for storing visual regression baselines under `missions/<id>/snapshots/`; defines naming scheme, breakpoints (320, 768, 1024, 1440), and how the user-testing validator compares new snapshots against the baseline.

### Known gaps
- No UI exists in the harness itself, so the anti-template gate and snapshot convention ship as documentation and protocol only. Both are exercised when the harness drives work on a UI-bearing project. Full end-to-end visual regression (Playwright screenshots, baseline diff) is deferred to the first qualifying UI mission.

## [0.7.0] — 2026-05-23

### Added
- Session ID stamping in `SessionStart` hook and `/mission-start` skill — every state mutation now records `session_id` so a resumed session can distinguish its own writes from a previous session's writes.
- `scripts/mission-checkpoint.sh` — checkpoint protocol that serialises remaining-work state into `missions/<id>/checkpoint.json`; invoked automatically after every feature completion and on `Stop`. The checkpoint captures: remaining feature list, last completed feature sha, orchestrator MEMORY.md digest, and timestamp.
- `checkpoint.json` template in `templates/` — schema for the checkpoint document emitted by `mission-checkpoint.sh`.
- `/mission-resume` skill updated with checkpoint-aware context injection: on session start it reads `checkpoint.json` (if present) and reconstructs the orchestrator's working state before any new prompt is processed.

### Changed
- ROADMAP v0.7 exit criterion reinterpreted under AI velocity (calendar-day framing → "session-boundary resume"): a mission interrupted mid-feature can be resumed in a fresh session via `checkpoint.json` + `/mission-resume` without loss of state. The original literal criterion (day-3 pause → day-5 resume across two human-launched sessions) is preserved in Known gaps below.

### Known gaps
- Full end-to-end multi-Claude-session resume (literal exit criterion: mission paused day 3, restarted day 5 in a brand-new `claude` process) requires a second human-launched session to verify. The Orchestrator handles the HOW but cannot spawn a parent CLI process from inside a session. F005 smoke-tests the resume mechanism via simulation; real cross-session validation is tracked as a v0.7.1 follow-up.
- `mission-checkpoint.sh` is wired into the `Stop` hook but not yet wired into the `SubagentStop` hook; checkpoints are therefore session-granular, not feature-granular. Fine-grained per-feature checkpointing is a v0.7.1 improvement.

## [0.6.0] — 2026-05-23

### Added
- `scripts/mission-tui.sh` — terminal UI that renders active feature, last handoff summary, and pending validation status using `watch`, `jq`, and `glow`. Gives a human-readable mission-control view without opening any markdown file.
- `scripts/mission-html-report.sh` — generates a self-contained HTML mission report from `status.json`, `log.md`, and feature handoffs; opened in the default browser at mission close.
- `scripts/mission-diff.sh` — side-by-side diff of `plan.md` (original intent) vs `log.md` (actual execution timeline); highlights scope drift and unplanned follow-up features.

### Known gaps
- TUI exit criterion — "a non-engineer can glance at the TUI and answer where the mission is" — is **operator-side validation, not automatable in-session**. It requires a human observer running `mission-tui.sh` against a live mission. Deferred to first qualifying mission use; tracked as a v0.6.1 follow-up.
- `mission-html-report.sh` generates a static file but does not auto-open on Linux (uses `xdg-open`; macOS uses `open`). Cross-platform behaviour verified only on macOS.

## [0.5.0] — 2026-05-23

### Added
- `.claude/skills/explore/` — `/explore` skill that accepts one or more questions, fans out a dedicated `explorer` subagent per question in parallel, and synthesises the results into a single planning brief.
- `protocols/parallel-exploration.md` — formal rules for when the Orchestrator may fan out explorer subagents: read-only work only, max concurrency guidelines, synthesis step required before any Worker is spawned.
- `.claude/settings.json` PreToolUse hook on the `Agent` tool — blocks any attempt to spawn a non-`explorer` subagent concurrently, enforcing the serial-execution rule for Workers and Validators at the shell level.

### Changed
- `CLAUDE.md` section 3 updated to reference the new `parallel-exploration.md` protocol and the `/explore` skill.
- `protocols/serial-execution.md` cross-references `protocols/parallel-exploration.md` for the fan-out carve-out.

### Known gaps
- `/explore` skill is registered in `.claude/skills/` but is **not invocable in the current session** — the skill registry is session-static (the same limitation documented for Scout in v0.4); it will be available from the next fresh session onward.
- The v0.5 exit criterion — "plan phase uses ≥3 parallel explorers and produces a measurably better plan" — is **infrastructure ready, real-world verification deferred**. Demonstrating the improvement requires a complex mission whose planning phase exercises the fanout; this will be tracked as a follow-up against the first qualifying mission.
- PreToolUse hook IS live and verified (exit code 0 in contract checks).

## [0.4.0] — 2026-05-23

### Added
- `.claude/agents/scout.md` — Scout subagent with `memory: project` enabled; accumulates cross-mission learnings without polluting Worker or Scrutiny Validator fresh-context guarantees.
- `scripts/learnings-index.sh` — auto-regenerates `learnings/INDEX.md` from the contents of `learnings/patterns/` and `learnings/anti-patterns/`; wired so the index stays current after every `/mission-review`.
- `protocols/self-review.md` — quarterly self-review protocol: orchestrator reads its own `agent-memory/MEMORY.md`, surfaces recurring mistakes, proposes protocol edits.
- `protocols/ab-compare.md` — A/B compare protocol: pick two similar past missions, diff their post-mortems, surface the quality delta.

### Changed
- `learnings/INDEX.md` is now auto-regenerated by `scripts/learnings-index.sh`; manual edits to the index are no longer expected.

### Known gaps
- The v0.4 exit criterion — "a mission similar to a past one shows measurably better outcomes (fewer follow-up features, fewer validator failures)" — is **infrastructure ready, real-world verification deferred**. Demonstrating the improvement requires running a second mission of similar shape and comparing post-mortems. This is wall-clock-bound by design; the comparison will be performed in a follow-up mission once sufficient history accumulates.

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
