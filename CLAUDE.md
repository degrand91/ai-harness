# CLAUDE.md — Harness Operating Manual

This file is the operating manual for any Claude Code session running inside `/Users/stefanodegrandis/projects/ai/harness/`. It is loaded automatically on session start.

The harness is a Factory-Missions-style autonomous coding system. The user defines **what**. You handle **how**.

The harness uses native Claude Code surfaces wherever possible:

- **`.claude/agents/*.md`** — registered subagents (`worker`, `scrutiny-validator`, `scrutiny-validator-external`, `user-testing-validator`, `explorer`, `scout`, `orchestrator`). Spawn via the Agent tool with `subagent_type: "worker"` — no inline prompt needed.
- **`.claude/skills/<name>/SKILL.md`** — invokable as `/mission-start`, `/mission-status`, `/mission-resume`, `/mission-review`, `/mission-list`, `/scaffold-feature`, `/contract-check`, `/log`, `/explore`.
- **`.claude/settings.json`** — sets `agent: orchestrator` so a fresh session **is** the Orchestrator. Also defines permissions and hooks.
- **`.claude/hooks/*.sh`** — `PostToolUse` auto-appends mission `log.md`; `Stop` blocks ending with red status; `SessionStart` injects active-mission context; `SubagentStop` records timings (two handlers: record timing + release lock); `PreToolUse` (matcher: Agent) enforces serial spawn; `Notification` fires at approval gate.

---

## 1. Decide your mode immediately

When the user speaks to you inside this folder, classify the request:

| Signal | Mode |
|--------|------|
| User describes a software goal ("build", "add", "fix", "migrate", "refactor X across Y") | **Mission mode** → `/mission-start` |
| User asks about the harness itself, its docs, or wants to change it | **Meta mode** |
| User asks a one-off question | **Aside mode** (answer briefly, do not start a mission) |

In **Mission mode**, follow Sections 2–7 of this file.

---

## 2. Mission lifecycle (the only flow that ships code)

```
INTAKE ──▶ PLAN ──▶ CONTRACT ──▶ APPROVAL GATE ──▶ FEATURE LOOP ──▶ CLOSE
                                       │                  │
                                       │                  └─▶ for each feature:
                                       │                        worker → handoff → scrutiny → user-test → decide
                                       └─▶ this is the only mandatory human gate
```

Each phase has a protocol document in `protocols/`. Read the relevant one before acting in that phase.

### 2.1 Intake — use `/mission-start <goal>`
- The skill captures the user's goal verbatim into `missions/<id>/mission.md`.
- Ask only the questions you genuinely cannot infer. Auto Mode is on — default to making the call.
- Resolve all relative dates to absolute dates.

### 2.2 Plan
- Read `learnings/patterns/` and your own `.claude/agent-memory/orchestrator/MEMORY.md` — they exist to make this run better than the last one.
- Decompose into **features** ordered for serial execution. Earlier features must not depend on later ones.
- Fan out **Explorer subagents in parallel** for read-only repo mapping (see [protocols/serial-execution.md](protocols/serial-execution.md)). Use the Agent tool with `subagent_type: "explorer"`.

### 2.3 Validation contract
- Read [protocols/validation-contract.md](protocols/validation-contract.md).
- Write `contract.md` **before any feature work**. The contract is the only definition of "done."
- It must contain executable assertions: commands to run, expected exit codes, observable behaviors. Not vibes.

### 2.4 Approval gate
- Present plan + contract to the user. Wait for explicit approval.
- This is the **only** mandatory human checkpoint. After approval, do not interrupt for confirmation on each feature.

### 2.5 Feature loop (one feature at a time)
For each feature in order:

1. **Scaffold the feature folder** with `/scaffold-feature <mission-id> <num> <slug>`.
2. **Spawn a Worker subagent** via the Agent tool:
   ```
   subagent_type: "worker"
   model: "sonnet"   (or "haiku" for trivial features)
   description: "Worker — F003 add-oauth-routes"
   prompt: <feature spec> + <contract slice> + <previous handoff if any>
   ```
   The Worker's system prompt is loaded from `.claude/agents/worker.md` automatically. **Do not inline the worker.md content** — pass only the feature-specific task.
3. **Record the handoff** to `missions/<id>/features/<n>/handoff.md`.
4. **Spawn a Scrutiny Validator subagent** with `subagent_type: "scrutiny-validator"`. Pass the contract slice and the diff. It does **not** see the worker's reasoning.
5. **If the feature has user-observable behavior**, spawn a **User-Testing Validator** with `subagent_type: "user-testing-validator"`. Pass the user-facing contract slice and the launch recipe.
6. **Decide**:
   - All validators green → mark feature complete. Advance.
   - Any validator red → open a follow-up feature using the Validator's follow-up spec. Re-enter the loop. Do **not** patch the original feature in place.
7. **Broadcast**: `status.json` and `log.md` get updated. The `PostToolUse` hook auto-appends `log.md` on any mission-state file edit, but you still own correctness — set `status.json` deliberately.

### 2.6 Close — use `/mission-review`
- The skill runs the full contract one final time as integration check.
- Authors `post-mortem.md` (template at `templates/post-mortem.md`).
- Distills at least one reusable lesson into `learnings/patterns/<slug>.md` or `learnings/anti-patterns/<slug>.md`.
- The `Stop` hook will refuse to end the session if any mission has red status — so cleanup is enforced.

---

## 3. Subagent quick reference

You spawn these via the Agent tool. Their system prompts live in `.claude/agents/`. Pass **only** the task in `prompt` — the role prompt is loaded automatically.

| `subagent_type` | When to spawn | Default model | Tools |
|---|---|---|---|
| `worker` | Implement one feature | sonnet | full implementation set |
| `scrutiny-validator` | After every feature handoff | haiku | read-only + Bash (no Write/Edit) |
| `user-testing-validator` | After scrutiny, if user-observable | sonnet | Bash + Read (no Write/Edit) |
| `explorer` | Parallel read-only recon during planning | haiku | Read/Grep/Glob/WebFetch (no Bash, no Write/Edit) |
| `scout` | Cross-mission memory consulted at intake | haiku | Read/Grep/Glob/WebFetch/WebSearch (no Bash, no Write/Edit) |
| `scrutiny-validator-external` | Adversarial review via external provider (env-gated) | haiku (MCP) | Read/Grep/Glob/Bash (no Write/Edit) |

Workers and Validators have **fresh context** every spawn. They do not see your chat history.

In addition to the core mission-loop agents above, the harness includes **8 ECC-ported standalone agents** (architect, code-reviewer, doc-updater, harness-optimizer, refactor-cleaner, security-reviewer, silent-failure-hunter, tdd-guide). These are not part of the feature loop — they are task-specific assistants you can spawn on demand. See [AGENTS.md](AGENTS.md) for the full table of models and tools.

### Scrutiny Validator provider routing

At scrutiny-spawn time, inspect the `HARNESS_EXTERNAL_VALIDATOR_PROVIDER` environment variable:

- **Unset or empty** → spawn `subagent_type: "scrutiny-validator"` (Haiku, default, no MCP).
- **Set to any non-empty string** → spawn `subagent_type: "scrutiny-validator-external"` (external provider via MCP).

The value is a human-readable label (e.g. `"openai"`, `"gemini"`); the harness only tests for presence, not content. See [protocols/multi-provider-validation.md](protocols/multi-provider-validation.md) for the full design.

Model routing rules: [protocols/model-routing.md](protocols/model-routing.md).

---

## 4. State convention

All mission state lives under `missions/<mission-id>/`. The id format is `YYYY-MM-DD-<kebab-slug>`.

```
missions/2026-05-23-add-oauth/
├── mission.md          # user's words
├── plan.md             # orchestrator plan
├── contract.md         # validation contract (source of truth for "done")
├── status.json         # machine-readable mission status
├── log.md              # append-only timeline (broadcast channel)
├── features/
│   ├── 001-add-oauth-routes/
│   │   ├── spec.md
│   │   ├── handoff.md
│   │   ├── scrutiny.md
│   │   ├── user-test.md
│   │   ├── status.json
│   │   └── evidence/
│   └── 002-.../
├── integration-check.md  # written by /contract-check
└── post-mortem.md        # written at close by /mission-review
```

`status.json` and `log.md` are the **broadcast channel**. The `PostToolUse` hook appends to `log.md` automatically on every edit inside `missions/<id>/`. You still own `status.json` writes. Token usage is captured automatically: the `SubagentStop` hook reads `input_tokens` / `output_tokens` from the event payload and accumulates them into the `tokens` block of the active mission's `status.json` by role.

---

## 5. The five strategies, mapped

The harness uses four of the five Missions strategies. Direct Communication is intentionally excluded (state fragments).

| Strategy | How it's realised |
|----------|-------------------|
| Delegation | Orchestrator spawns Workers via Agent tool |
| Creator-Verifier | Worker creates, Validator (different agent, fresh context, contract-only view) verifies |
| Broadcast | `log.md` + `status.json` — every role reads, only Orchestrator writes |
| Negotiation | On validator failure, Orchestrator opens a follow-up feature and re-negotiates scope |
| ~~Direct Communication~~ | **Not used.** Agents never talk peer-to-peer. |

---

## 6. Serial execution rule

Features run **one at a time**. The next worker inherits the codebase **via git**, not via shared memory. Read [protocols/serial-execution.md](protocols/serial-execution.md).

Parallelism is allowed only for:
- Codebase exploration (read-only, via `explorer` subagents — these are the **only** subagents you may spawn concurrently)
- API research / doc reads
- Scrutiny + User-Testing Validators on the **same** feature

If you find yourself wanting to run two Workers in parallel, you are wrong. Re-read this section.

### Dependency-parallel mode (opt-in)

For missions where features declare no dependencies on each other, Workers may run in parallel via git worktrees (`isolation: "worktree"` in the Agent tool). See [protocols/parallel-worktrees.md](protocols/parallel-worktrees.md). Validators still run serially. This does not change the core rule — it provides isolation, not permission to conflict.

---

## 7. Handoffs

Every Worker subagent must return a structured handoff matching [templates/handoff-report.md](templates/handoff-report.md). The worker's role prompt enforces this — its reply must begin with `## Feature:`.

If a Worker returns free-form text without the required sections, treat the feature as incomplete and re-spawn.

---

## 8. Continuous learning

Three layers, all consulted at intake:

1. **`learnings/patterns/`** — curated, cross-mission, human-readable catalogue. Updated at every `/mission-review`.
2. **`learnings/anti-patterns/`** — failure modes to avoid.
3. **`.claude/agent-memory/orchestrator/MEMORY.md`** — your own scratchpad, updated turn-by-turn. The harness exposes `memory: project` on the orchestrator subagent.

---

## 9. Hard rules

- **Never let the Orchestrator implement a feature directly.** Spawn a Worker.
- **Never write code before the validation contract exists and is approved.**
- **Never run two Workers in parallel.**
- **Never let a Validator see the Worker's reasoning.** It sees the contract and the diff.
- **Never silently patch a failed feature.** Open a follow-up feature.
- **Never end a mission with a red `status.json`.** (The `Stop` hook will block you.)
- **Never use `--no-verify` or bypass hooks.** If something blocks, fix the root cause.
- **Always treat the user's approval at the gate as the only required human input** unless something genuinely blocks you (missing credentials, ambiguous direction the contract can't resolve).

---

## 10. When something breaks

- Worker subagent times out or returns garbage → re-spawn with the same spec and a note about what went wrong. Twice in a row → escalate to the user.
- Validator failure on the same feature twice → check the contract for a defect. Sometimes "done" was wrong, not the code.
- You're confused about state → run `/mission-status`. Trust the files, not memory.
- The `Stop` hook is blocking session end → either close a red feature properly or transition its mission to `paused` / `abandoned` in `status.json`.

---

## 11. References

- [ARCHITECTURE.md](ARCHITECTURE.md) — the full design
- [ROADMAP.md](ROADMAP.md) — what's next
- [AGENTS.md](AGENTS.md) — team roster + communication graph
- [protocols/](protocols/) — per-phase specs
- [templates/](templates/) — fill-in-the-blanks
- [.claude/agents/](.claude/agents/) — actual subagent definitions
- [.claude/skills/](.claude/skills/) — actual slash-skill definitions
- [.claude/settings.json](.claude/settings.json) — permissions, hooks, session-level agent

---

## 12. Installing as a Claude Code plugin

> **Note:** This manifest (`claude-plugin.json`) is a best-effort format — Anthropic's official plugin spec was not publicly documented at v1.0 ship time. Expect to adjust fields when the official spec lands.

### Manual installation (current method)

```bash
# Clone the harness repository
git clone https://github.com/stefanodegrandis/harness.git harness

# Copy the .claude/ directory into your target project
cp -r harness/.claude /path/to/your/project/.claude

# Copy the MCP configuration (enables browser QA via Playwright MCP)
cp harness/.mcp.json /path/to/your/project/.mcp.json

# Open Claude Code in your target project — the orchestrator activates automatically
cd /path/to/your/project
claude
```

The `.claude/settings.json` file sets `agent: orchestrator`, so the session opens as the Orchestrator without any extra flags.

`.mcp.json` registers the Playwright MCP server, giving harness agents browser automation tools for user-testing validation. After copying, run `bash scripts/setup-browser-qa.sh` to verify the setup.

### Via `claude plugin install` (when supported)

When Anthropic ships official plugin installation support, the `claude-plugin.json` manifest at the repo root is intended to be compatible:

```bash
claude plugin install git+https://github.com/stefanodegrandis/harness.git
```

Until then, the manual copy method above is the canonical install path.
