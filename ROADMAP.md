# Roadmap

The harness is intentionally small at v0.1 and grows by iteration. Every mission should leave it slightly better.

Each phase below lists a concrete deliverable and an exit criterion. Don't ship a phase early.

---

## v0.1 — Foundations (this commit)

**Deliverables**
- Protocols (lifecycle, roles, contract, handoff, serial execution, model routing)
- Templates (mission spec, contract, handoff, post-mortem, feature spec)
- Subagent prompt files in `agents/`
- `commands/mission-start.md` instructs Claude to scaffold mission folders inline (no shell scripts — templates are the source of truth)
- `scripts/status.sh` — the only shell script, so users can check state without spending tokens
- CLAUDE.md operating manual
- One worked example mission

**Exit criterion.** Claude can be told "Run mission X" inside the harness folder and follow the protocol end-to-end without external tooling.

---

## v0.2 — Automation of the boring parts

**Goal**: remove repetitive Claude bookkeeping — but only with helpers whose work can't be done inside a Claude session.

The rule of thumb: **a shell script earns its place only if it has a real Claude-free use case** (cron, hook, status check, CI). Bookkeeping that always happens inside a session stays in the session.

- `scripts/contract-check.sh` — runs all executable assertions in `contract.md` and writes a machine-readable verdict file. Useful from CI and from Stop hooks. Already has a Claude-free use case.
- `scripts/log-tail.sh` — like `status.sh` but follows `log.md` live for long missions. Pure ops tool.
- JSON schemas for `status.json` and feature `status.json` under `schemas/`, so any tool (not just Claude) can validate state.
- **Explicitly not added**: `mission-init.sh`, `feature-init.sh`, `handoff-record.sh`. These run only inside a session — Claude does them with Write.

**Exit criterion.** `contract.md` can be evaluated end-to-end without a Claude session (e.g. from CI).

---

## v0.3 — Hook-enforced procedure

**Goal**: the harness enforces its own rules instead of relying on Claude remembering them.

- `hooks/pre-write-block-direct-impl.sh` — PreToolUse hook that blocks the Orchestrator from writing code outside `missions/` (workers operate from subagent context, not the main session).
- `hooks/post-edit-update-log.sh` — PostToolUse hook that appends to `log.md` whenever a feature folder changes.
- `hooks/stop-no-red-status.sh` — Stop hook that refuses to end if any feature's `status.json` is red.
- `hooks/pre-subagent-inject-contract.sh` — PreToolUse hook on Agent calls that auto-injects the relevant contract slice.

**Exit criterion.** A new Claude session cannot accidentally break protocol — the hooks stop it.

---

## v0.4 — Learning loop

**Goal**: make the harness better with each completed mission.

- `learnings/patterns/<slug>.md` — distilled lessons from post-mortems.
- `scripts/learnings-index.sh` — regenerates `learnings/INDEX.md`.
- Orchestrator prompt automatically receives the top-N relevant patterns based on the mission spec.
- `learnings/anti-patterns/` — things that failed; the orchestrator avoids them.
- Quarterly self-review: orchestrator reads its own past plans, identifies recurring mistakes, proposes protocol edits.

**Exit criterion.** A mission similar to a past one shows measurably better outcomes (fewer follow-up features, fewer validator failures).

---

## v0.5 — Multi-provider model routing

**Goal**: realise the "different model in each role" principle, including across providers.

- `protocols/model-routing.md` extended with provider-aware decision tree.
- Validator role can be routed to a non-Claude provider when configured (via an MCP server or external CLI), specifically to avoid training-data bias on Claude-written code.
- Per-role token budgets recorded in `status.json`.
- Cost report in `post-mortem.md`.

**Exit criterion.** A mission's `post-mortem.md` reports per-role model, tokens, and cost. Validator runs on a different provider than the worker.

---

## v0.6 — Parallel exploration

**Goal**: realise the "parallelism only for read-only work" principle.

- `agents/explorer.md` — read-only subagent for codebase mapping, dep search, doc reads.
- `protocols/parallel-exploration.md` — when the orchestrator may spawn N explorers at once.
- `scripts/explorer-fanout.sh` — orchestrator helper that fans out exploration calls.
- Anti-pattern guard: explorers cannot edit files (enforced by subagent type and tool allowlist).

**Exit criterion.** Plan phase of a complex mission uses ≥3 parallel explorers and produces a measurably better plan.

---

## v0.7 — Mission Control surface

**Goal**: human-friendly progress without reading raw markdown.

- `scripts/mission-tui.sh` — a TUI (could be just `watch + jq + glow`) that shows active feature, last handoff, pending validation.
- HTML mission report generated at close.
- Mission diff view: side-by-side of `plan.md` (intent) vs `log.md` (actual).

**Exit criterion.** A non-engineer can glance at the TUI and answer "where is the mission?"

---

## v0.8 — Resumability & multi-session

**Goal**: a mission survives session crashes, restarts, and hand-offs between humans.

- `commands/mission-resume.md` — formal resume protocol.
- Session ID stamped in every state mutation.
- Checkpoint system: every N features the orchestrator emits a `checkpoint.json` summarising remaining work.
- "Pause and resume tomorrow" tested end-to-end.

**Exit criterion.** A mission paused on day 3, restarted on day 5 in a fresh Claude session, completes correctly.

---

## v0.9 — Anti-template & quality gates

**Goal**: kill generic-looking output, enforce taste.

- `protocols/design-quality.md` extends `~/.claude/rules/ecc/web/design-quality.md` for the harness.
- User-testing validator's prompt includes a "does this look like a default template?" gate.
- Visual regression baseline stored under `missions/<id>/snapshots/`.

**Exit criterion.** Validator can reject a feature for taste reasons, not just functional.

---

## v1.0 — Production

**Goal**: stable, documented, used.

- `docs/` complete: faq, glossary, troubleshooting, hook reference.
- `examples/` covers: greenfield app, refactor mission, bug-fix mission, migration mission.
- `CHANGELOG.md`.
- Versioned protocol files (`protocols/v1/`).
- The harness has run at least one ≥7-day mission successfully.

**Exit criterion.** Someone unfamiliar with the harness can read `README.md`, run a mission, and ship.

---

## Beyond v1.0 (sketch)

- Distributed orchestration: orchestrator on Opus, workers on a fleet of Sonnet sessions, coordinated via the filesystem.
- A `harness-doctor` command that audits a mission folder for protocol violations.
- Cross-mission analytics: which patterns recur, which validators trip most, which models cost most.
- A `harness eject` command that generates a final hand-off doc when the human takes over.

---

## How to propose a phase change

1. Open `learnings/proposals/<slug>.md`.
2. State the problem, the proposed change, the exit criterion.
3. The next mission's orchestrator considers it before locking the plan.
