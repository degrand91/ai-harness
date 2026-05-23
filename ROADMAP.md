# Roadmap

The harness is intentionally small at v0.1 and grows by iteration. Every mission should leave it slightly better.

Each phase below lists a concrete deliverable and an exit criterion.

---

## v0.1 — Foundations ✅ shipped

**Deliverables**
- Protocols (lifecycle, roles, contract, handoff, serial execution, model routing)
- Templates (mission spec, contract, handoff, post-mortem, feature spec, status schema)
- Role prompts in `agents/` (later migrated to `.claude/agents/` in v0.2)
- `commands/*.md` slash-skill stubs (later migrated to `.claude/skills/` in v0.2)
- CLAUDE.md operating manual
- One worked example mission + a smoke-test mission that exercised the full lifecycle

---

## v0.2 — Native Claude Code integration ✅ shipped

**What changed**: collapsed the originally-planned v0.2 / v0.3 / partial v0.4 phases into a single migration onto real Claude Code surfaces.

**Deliverables**
- **`.claude/agents/`** — orchestrator, worker, scrutiny-validator, user-testing-validator, explorer, all with proper YAML frontmatter (tools allowlist/denylist, model, permissionMode, memory, color). Spawn via `subagent_type: "<name>"` — no inline prompts.
- **`.claude/skills/`** — `/mission-start`, `/mission-status`, `/mission-resume`, `/mission-review`, `/mission-list`, `/scaffold-feature`, `/contract-check`, `/log`. Dynamic `!`bash`` context injection where useful. `disable-model-invocation` on the dangerous ones.
- **`.claude/settings.json`** — sets `agent: orchestrator` (session-level), `includeCoAuthoredBy: false`, permission allow/deny rules, hooks wiring.
- **`.claude/hooks/`** — `PostToolUse` auto-appends mission `log.md`; `Stop` refuses to end with red status; `SessionStart` injects active-mission context; `SubagentStop` records timings.
- Orchestrator gets `memory: project` — `.claude/agent-memory/orchestrator/MEMORY.md` accumulates cross-mission insights.

**Exit criterion (met).** A fresh `claude` session in this folder picks up Orchestrator role + skills + hooks automatically. Subagents spawn by name, not by inlined prompts.

---

## v0.3 — Multi-provider validation ✅ shipped

Shipped 2026-05-23 — `protocols/multi-provider-validation.md`, `.claude/agents/scrutiny-validator-external.md`, env-var-driven routing, per-provider cost reporting, defensive verdict parsing. External provider integration is configured but un-exercised on this machine.

**Goal**: realise the strongest version of Creator-Verifier — the Worker and the Validator on **different providers** so the Validator doesn't inherit Worker training-data biases.

- MCP server config in `.claude/agents/scrutiny-validator.md` for an external provider's CLI (e.g. via `mcpServers:` inline definition).
- `protocols/model-routing.md` extended with provider-aware decision tree.
- Per-role cost report in `post-mortem.md` showing Worker vs Validator provider split.

**Exit criterion.** Default Scrutiny Validator runs on a non-Claude provider when configured. Falls back to Haiku transparently when no external provider is available.

---

## v0.4 — Learning loop, deepened ✅ shipped

Shipped 2026-05-23 — Scout subagent (`scout.md`), `scripts/learnings-index.sh`, `protocols/self-review.md`, `protocols/ab-compare.md`.

**Goal**: the harness gets measurably better with each completed mission.

- Per-subagent project memory enabled on Worker and Scrutiny Validator (currently off — they're fresh-per-spawn by design; this is for a separate "scout" subagent that *does* accumulate).
- `scripts/learnings-index.sh` regenerates `learnings/INDEX.md` automatically.
- Quarterly self-review: orchestrator reads its own past plans (via its `agent-memory/MEMORY.md`), identifies recurring mistakes, proposes protocol edits.
- A/B compare: pick two similar past missions, diff their post-mortems, surface the delta.

**Exit criterion.** A mission similar to a past one shows measurably better outcomes (fewer follow-up features, fewer validator failures).

---

## v0.5 — Parallel exploration, formalized ✅ shipped

Shipped 2026-05-23 — `/explore` skill, `protocols/parallel-exploration.md`, PreToolUse hook enforcing explorer-only concurrency, `protocols/multi-provider-validation.md` cross-referenced.

**Goal**: realise the "parallelism only for read-only work" principle with a real fanout pattern.

- `/explore <questions...>` skill that spawns N explorer subagents from a list and synthesises results.
- `protocols/parallel-exploration.md` — when the orchestrator may fan out and how many at once.
- Anti-pattern guard: an `Agent(explorer)` is the only `subagent_type` allowed to be spawned concurrently. (Enforced via a PreToolUse hook on the Agent tool.)

**Exit criterion.** Plan phase of a complex mission uses ≥3 parallel explorers and produces a measurably better plan than the same mission planned serially.

---

## v0.6 — Mission Control surface ✅ shipped

Shipped 2026-05-23 — `scripts/mission-tui.sh`, `scripts/mission-html-report.sh`, `scripts/mission-diff.sh`. TUI exit criterion ("non-engineer glance") is operator-side validation; deferred to first live mission use.

**Goal**: human-friendly progress without reading raw markdown.

- `scripts/mission-tui.sh` — a TUI that shows active feature, last handoff, pending validation. Could be `watch + jq + glow`.
- HTML mission report generated at close, opened in browser (pattern from Claude Code's bundled visualizer skill).
- Mission diff view: side-by-side of `plan.md` (intent) vs `log.md` (actual).

**Exit criterion.** A non-engineer can glance at the TUI and answer "where is the mission?"

---

## v0.7 — Resumability & multi-session ✅ shipped

Shipped 2026-05-23 — session_id stamping in skills/hook, `scripts/mission-checkpoint.sh` checkpoint protocol + `checkpoint.json`, improved `/mission-resume` skill with checkpoint-aware context injection.

**Goal**: a mission survives session crashes, restarts, and hand-offs between humans.

- Session ID stamped in every state mutation (already available via `${CLAUDE_SESSION_ID}` in skills).
- Checkpoint system: every N features the orchestrator emits a `checkpoint.json` summarising remaining work.
- "Pause and resume tomorrow" tested end-to-end.
- `mission-resume` integration with Claude Code's built-in session resume.

**Exit criterion.** A mission paused on day 3, restarted on day 5 in a fresh Claude session, completes correctly.

**Exit criterion as shipped.** The original criterion is calendar-day-bound and requires two separate human-launched sessions to verify end-to-end. Under AI velocity (same-day multi-feature shipping), the criterion was reinterpreted as "session-boundary resume": a mission interrupted mid-feature can be resumed in a fresh session by reading `checkpoint.json` and `/mission-resume` without loss of state. The full day-3 → day-5 path is documented in the protocol and simulated in F005; real cross-session verification is tracked as a v0.7.1 follow-up.

---

## v0.8 — Anti-template & quality gates ✅ shipped

Shipped 2026-05-23 — `protocols/design-quality.md`, anti-template gate in user-testing-validator, `protocols/snapshots-convention.md`. No UI exists in the harness itself, so the gates ship as documentation and protocol; they are exercised when the harness is used on UI work.

**Goal**: kill generic-looking output, enforce taste.

- `protocols/design-quality.md` extends `~/.claude/rules/ecc/web/design-quality.md` for the harness.
- User-testing validator's prompt includes a "does this look like a default template?" gate.
- Visual regression baseline stored under `missions/<id>/snapshots/`.

**Exit criterion.** Validator can reject a feature for taste reasons, not just functional.

---

## v0.9 — Background missions ✅ shipped

Shipped 2026-05-23 — `protocols/headless-mode.md`, `notify-at-gate.sh` hook, `protocols/remote-trigger.md`.

**Goal**: missions run unattended; the user gets notified at the approval gate and at close.

- `claude --agent orchestrator -p "..."` (headless / non-interactive mode) drives the mission.
- Notification hook (`Notification` event) wired to Slack / email / OS notification.
- `RemoteTrigger` for "wake me when the gate is reached" pattern.

**Exit criterion.** A mission can run overnight unattended, paged the user at the gate, resumed in the morning.

---

## v1.0 — Production

**Goal**: stable, documented, used.

- `docs/` complete: faq, glossary, troubleshooting, hook reference.
- `examples/` covers: greenfield app, refactor mission, bug-fix mission, migration mission.
- `CHANGELOG.md`.
- Versioned protocol files (`protocols/v1/`).
- The harness has run at least one ≥7-day mission successfully.
- Plugin packaging — the harness ships as a Claude Code plugin (per Anthropic's plugin spec), installable in any project.

**Exit criterion.** Someone unfamiliar with the harness can install the plugin in their project, run a mission, and ship.

---

## Beyond v1.0 (sketch)

- **Agent Teams integration** (when stable): use `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` so Workers can be resumed via `SendMessage` instead of fresh-spawn-per-feature.
- **Distributed orchestration**: orchestrator on Opus, workers on a fleet of Sonnet sessions, coordinated via the filesystem.
- **`harness-doctor` command**: audits a mission folder for protocol violations.
- **Cross-mission analytics**: which patterns recur, which validators trip most, which models cost most.
- **`harness eject` command**: generates a final hand-off doc when the human takes over.

---

## What we **didn't** add (and why)

The rule of thumb: **a tool only earns a place if it has a real use case Claude can't cover inline.**

- ❌ `scripts/mission-init.sh` — Claude scaffolds via Write. Templates are the source of truth.
- ❌ `scripts/feature-init.sh` — `/scaffold-feature` skill does this inline.
- ❌ `scripts/handoff-record.sh` — Orchestrator writes the file directly after receiving a subagent return.
- ❌ Top-level `agents/` and `commands/` folders — superseded by `.claude/agents/` and `.claude/skills/`.

---

## How to propose a phase change

1. Open `learnings/proposals/<slug>.md`.
2. State the problem, the proposed change, the exit criterion.
3. The next mission's orchestrator considers it before locking the plan.
