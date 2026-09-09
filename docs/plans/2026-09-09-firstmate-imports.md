# Plan: harness as central control plane

Status: **COMPLETE.** All five phases merged, plus four follow-up passes.

| Phase | PR | What |
|---|---|---|
| 0 | #1 | test suite, CI, session lock, six hook defects |
| 1 | #2, #3 | project registry, snapshot layer, inbox, knowledge routing, renderer migration |
| 2 | #4 | durable decision holds |
| 3 | #5 | crewmates as headless processes in their own worktrees |
| 4 | #6 | turn-end guard primary, asyncRewake watcher, away mode |
| 5 | #7 | learnings lifecycle, memory budget, named leases |
| — | #8 | five bugs found by the first real crewmate run |
| — | #9 | README rewrite, crew window rendering, tmux backend verified |
| — | #10 | **wired the orchestrator to the crew** (it could not reach it) |
| — | #11 | reconciled the deep docs; labelled every protocol's status |
| — | #12 | collapsed the bash/jq/python seams |

**Deviations from this plan, and why** — each is marked in place below:

- §3.1 `trust.sh` — **not needed**. Headless mode skips the workspace-trust
  dialog, which the spike proved before any code was written.
- §3.3c `usage.sh` — folded into `run.sh`, which reads cost straight from the
  stream-json result event rather than scraping a transcript.
- §4.1 `user-prompt-reset-epoch.sh` — merged into `user-prompt-restore.sh`; both
  jobs mean "the captain spoke", and splitting them would give that fact two
  owners.
- §5.4 retire the in-process worker — **withdrawn**; the condition was vacuous
  and the goal was wrong.
- §1.1 `project-mode.sh` — named `project.sh`, since it also lists and adds.

**Goal.** The harness becomes the single place from which all AI project work is
started, watched, decided, and remembered — not a per-mission tool that happens
to live in one folder.

**The load-bearing change is Phase 3.** With in-process subagents a central
control plane is impossible: the controller is blocked inside a tool call for the
entire duration of any work it dispatches. Everything else here is structure
around that.

No firstmate code is copied. Its implementations are entangled with secondmates,
remote homes, and a seven-harness adapter layer we are explicitly not taking.
What is borrowed is mechanism and convention.

---

## Conventions adopted repo-wide (apply to every phase)

Four habits from firstmate that are worth more than any single feature:

1. **Single-owner declarations.** Every script header names what it is the single
   owner of. "Where does this belong" becomes answerable instead of arguable.
2. **The header is the doc.** `usage()` is `sed -n '2,12{s/^# \{0,1\}//;p;}' "$0"`.
   Help text cannot drift from the header comment because it *is* the header.
3. **Fail closed on ambiguity.** `fm-send.sh` refuses to run unless `FM_HOME` is
   explicit; `fm-startup-memory-budget.sh` errors on a malformed value rather
   than inferring a default. Contrast `stop-turnend-guard.sh:31`, which infers
   `"unknown"` and sails straight past the mission it was meant to guard.
4. **Two-layer commands.** One script emits a stable JSON contract; renderers
   consume it and never parse state themselves (`fm-fleet-view.sh:3-5`).

## Measurement note (corrected)

An earlier revision of this plan recorded a "host constraint" claiming process
spawning cost ~200 ms per script on this machine. **That was wrong.** The
numbers were taken while a `brew install` was saturating the box. Measured on an
idle machine:

| | claimed | actual |
|---|---|---|
| `/bin/echo` | 49 ms | **3.2 ms** |
| `bash -c 'exit 0'` | 63 ms | **3.8 ms** |
| empty `#!/usr/bin/env bash` script | 207 ms | **6.3 ms** |
| `jq -n 1` | 163 ms | **4.8 ms** |

The host is ordinary. Never benchmark against a busy machine.

Two design decisions were justified with those bad numbers. Both survive on
their own merits, with corrected reasoning:

- **The observer guard spawns zero subshells on the owner path** and is not
  matched on `Bash`. At ~6 ms a per-`Bash` hook would in fact have been
  affordable, but enforcing the lock inside `scripts/crew/*` and
  `scripts/watch.sh` is still better: those scripts are already running a
  process, so the check is genuinely free, and the rule lives next to the
  action it guards.
- **The snapshot makes ONE `jq` pass over all missions.** Measured on 40
  fixture files: one invocation **6 ms**, forty invocations **201 ms**. The
  batch form is 33x better regardless of host speed, and `jq -n 'inputs'` with
  `input_filename` was verified to attribute each document to the right file.
  The original **< 200 ms on 40 missions** budget is restored.

## Layout and state (single owner: this section)

Every later phase names files under one of four roots. Nothing runtime-ish goes
anywhere else, and none of the four is tracked.

| Root | Holds | Lifetime |
|---|---|---|
| `missions/` | mission specs, contracts, features, handoffs, decision holds | durable, per mission (already gitignored) |
| `data/` | project registry, inbox, worktrees (`data/worktrees/<project>/<task>`), archived notes | durable, private |
| `state/` | task meta + ledgers, locks, epochs, `.afk`, `.watch-off`, close-pending intents, pre-compact snapshots | volatile; safe to delete when nothing is running |
| `config/` | operator choices: memory budget, learnings budget, wedge minutes | durable, private |

`.claude/agent-memory/` stays where it is (operator memory, already gitignored).
`.gitignore` gains `data/`, `state/`, `config/`. A `scripts/doctor.sh` (Phase 0)
materialises the four roots and checks tools; it installs nothing.

---

# Phase 0 — Reliability floor

**Why first.** There are 16 shell files across `scripts/` and `.claude/hooks/`,
zero tests, and no `.github/`. Phases 1–3 add roughly a dozen more, several of
them hooks that run on every turn. The `CONTRIBUTING.md:20` dog-food rule
produces a mission folder as evidence — that is a demo, not a regression gate.

The two defects below are both one-line fixture tests. Neither was noticed.

### 0.1 — status.json schema drift silently disables the Stop guard

38 of 39 missions use `.state`. The most recent one uses `.status` + `.phase`. `stop-turnend-guard.sh:31` reads `.state // "unknown"`;
`"unknown"` is absent from the skip `case`, so it falls through to a
`.features[] | select(.color == "red")` filter — and that mission's features
carry `scrutiny: "PASS"` with no `color` key at all. The guard reports clean on
the one mission most likely to be dirty.

*Fix:* `scripts/lib/status-read.sh`, single owner of reading a mission's state.
`status_state <file>` normalises `.state // .status // "unknown"` and maps the
drifted vocabulary (`in-progress` → `executing`, `feature-loop` → `executing`).
Unrecognised values are a loud error, not a silent pass. Every consumer reads
through it. No mission file is rewritten.

### 0.2 — SessionStart only ever considers one mission

`session-start-inject-status.sh:22` takes `ls -t | head -n1`. With two active
missions the second is invisible on resume.

*Fix:* iterate all missions whose normalised state is active; fixed cap of three
missions × five log lines until §5.2 replaces the constant with a budget.

### Files
- `tests/run.sh` (new, ~120 lines) — dependency-free runner over `tests/*.test.sh`.
  No bats: neither bats nor shellcheck is installed locally, and firstmate's own
  202 tests are plain `*.test.sh` for exactly this reason.
- `tests/lib/fixtures.sh` (new) — build throwaway mission trees under `$TMPDIR`,
  assert exit codes and stderr shape, always clean up.
- `tests/hooks-*.test.sh` — one table-driven file per hook: fixture state →
  expected exit code and output. Covers all 8 existing hooks before any new one lands.
- `tests/scripts-*.test.sh` — coverage for `status.sh` and `status-read.sh`.
- `scripts/lib/status-read.sh` (new) — §0.1.
- `.github/workflows/ci.yml` (new) — `tests/run.sh` + shellcheck on macOS and Ubuntu.
- `scripts/lint.sh` (new) — shellcheck wrapper that installs nothing and skips
  cleanly when shellcheck is absent, so local runs never hard-fail on a missing tool.
- `scripts/doctor.sh` (new) — checks `git`, `gh` (authenticated), `jq`, `tmux`,
  `no-mistakes`, `claude` version; creates the four state roots; for every
  registered project runs `git worktree prune` and lists orphan `hc/*` branches
  older than 7 days with no matching `state/*.meta`; prints install commands and
  runs none of them. Borrowed shape from `fm-bootstrap.sh`.

### 0.3 — Session lock
Open the harness from a terminal and from the IDE and there are two
orchestrators and, later, two watchers dispatching. firstmate takes
`state/.lock` at SessionStart and every hook proves it descends from the owner
(`fm-session-lock-lib.sh`). Here the proof is simpler: every hook payload carries
`session_id`, so the lock records `{session_id, pid, started_at}` and a hook
compares.

- `.claude/hooks/session-start-lock.sh` — take `state/session.lock` if absent or
  its pid is dead; otherwise inject **OBSERVER MODE** context naming the owner.
- `.claude/hooks/pre-tool-observer-guard.sh` — in observer mode, block
  `Write`/`Edit` under `missions/`, and `Bash` calls to `scripts/crew/*` and
  `scripts/watch.sh`. `/fleet`, `/inbox note`, and reading stay allowed.
- `SessionEnd` releases the lock. Every later hook that acts (watcher, AFK,
  teardown) first checks `session_id` against the lock and exits 0 silently on
  mismatch — a second session can *look*, never *act*.
- `CONTRIBUTING.md` — dog-food rule gains: a hook or script change requires a test.
- `.claude/settings.json` — `permissions.allow` gains `Bash(./tests/run.sh *)`,
  `Bash(./scripts/doctor.sh *)`, `Bash(./scripts/lint.sh *)`. **Every phase below
  lists its own additions; a script with no allow entry prompts on every call.**

### 0.4 — The stuck-feature check had no age bound
`stop-turnend-guard.sh` documented "stuck `in_progress` for more than 1 hour"
but contained no age test at all, so it blocked the stop on *any* executing
mission with an in-progress feature — during normal operation, not just
abandonment.

*Fix:* compare `now` against the newest mtime of `status.json` and `log.md`,
threshold `HARNESS_STUCK_SECONDS` (default 3600).

### 0.5 — Three hooks crashed on malformed input
`post-write-mission-state.sh`, `pre-agent-spawn-serial.sh` and
`subagent-stop-release-lock.sh` all used `set -euo pipefail` with unguarded `jq`,
so any payload jq could not parse exited the hook non-zero instead of doing
nothing. For `pre-agent-spawn-serial.sh` that meant a **blocked tool call**.

*Fix:* `set -uo pipefail` and `|| true` on every `jq`. A hook fails OPEN.

### 0.6 — Hooks resolved code from the data root
Sourcing a library from `CLAUDE_PROJECT_DIR` silently disables a hook whenever
code and data roots differ. Every hook now resolves code from `BASH_SOURCE` and
data from `CLAUDE_PROJECT_DIR`, and a missing library is a loud refusal.

### Verification — done
- 10 test files, 94 assertions, green on this host.
- `scripts/lint.sh`: 35 shell files clean under shellcheck (4 findings fixed,
  2 of them pre-existing).
- §0.1 regression confirmed to bite: reverting the guard to read `.state`
  directly fails `hook-stop-turnend-guard.test.sh`.
- CI runs the suite on ubuntu-latest and macos-latest, plus shellcheck
  `--strict` on Ubuntu.

---

# Phase 1 — Control-plane structure

**Why.** This is the phase that answers the actual ambition. Today a project is a
`target_repo` string buried inside one mission's `status.json`; there is no
cross-project view, no per-project policy, and no way to capture work that is not
already a mission.

### 1.1 — Project registry

`data/projects.md`, one line per project:

```
- mobile-app [no-mistakes] ~/projects/mobile-app allow="bun *, npx expo *" - the flagship app (added 2026-05-21)
- forked-lib [direct-PR +yolo] ~/projects/forked-lib allow="cargo *" - fork release mirroring (added 2026-06-02)
- harness [local-only] ~/projects/harness allow="./tests/run.sh *" - this repo (added 2026-09-09)
```

`allow=` is the project's build/test command set, appended to the crew tool
allowlist at spawn (§3.1 step 3). Absent means the base allowlist only — a
crewmate that needs more writes `blocked:` rather than getting it silently.

The path is the project's **primary checkout**; the harness never clones into
itself. Crew worktrees (Phase 3) are linked worktrees of that checkout, placed
under `data/worktrees/<project>/<task>` so the project tree is never polluted.

Modes: `no-mistakes` (full pipeline → PR → merge authority), `direct-PR`
(push + PR, no pipeline), `local-only` (local branch, guarded local merge).
`+yolo` grants merge autonomy.

The design note worth copying is `fm-project-mode.sh:5-9`: the resolver answers
**"what posture did the captain register"** and explicitly *not* **"how does this
task ship."** Per-task delivery is decided at intake and passed explicitly, so a
task may deviate with a logged reason instead of silently rewriting the registry.

- `scripts/project.sh` (new; renamed from the plan's `project-mode.sh`, since it
  also lists, adds and validates) — `resolve` prints `<mode> <yolo> <path>`;
  unregistered is exit 1, never a default; malformed is exit 2.
  `scripts/lib/registry.sh` owns the format. Existing missions' `target_repo` fields are
  matched to the registry by path; an unmatched one is reported, not guessed.
- `.claude/skills/project/SKILL.md` (new) — `/project add|list|mode`.
- `protocols/project-registry.md` (new).
- `data/` added to `.gitignore` alongside the existing `missions/` entry — the
  registry is private operational state, matching firstmate's `data/` boundary.

### 1.2 — Snapshot layer

There are **38 `jq` call sites across 6 renderers** (`status.sh`,
`mission-tui.sh`, `mission-html-report.sh`, `mission-diff.sh`,
`mission-checkpoint.sh`, `harness-audit.sh`), each parsing `status.json`
independently. Six chances to drift, and §0.1 proves drift already happened.

- `scripts/snapshot.sh` (new) — the single owner of reading fleet state. Emits
  one stable JSON document: every registered project, its active missions,
  feature states, open decision holds, and last activity. Reads through
  `status-read.sh`.
- `scripts/fleet.sh` (new) — human renderer. Parses **nothing** itself; shells
  out to `snapshot.sh --json`.
- The snapshot carries **spend**: per mission, rolled up per project and per
  calendar day, from the `tokens` block plus the crew usage files of §3.3c.
  `/fleet` shows it. `config/spend-cap-daily` (USD, optional): when the day's
  roll-up crosses it, `spawn.sh` refuses and files a blocking hold — central
  control over AI development without cost visibility is half a control plane.
- Budget: **< 200 ms** on 40 missions, because the Phase 4 watcher polls it
  every cycle. Requires a SINGLE `jq` invocation over every status.json, using
  `jq -n 'inputs'` with `input_filename` to attribute each document to its
  mission — measured at 6 ms versus 201 ms for per-mission invocations. The
  suite asserts the timing on a 40-mission fixture. Closed and abandoned missions are skipped on a cheap `jq -r` of one
  field before anything else is read; the test suite asserts the timing on a
  40-mission fixture.
- Renderer migration: **done.** `fleet.sh` is snapshot-only by construction (its
  test asserts the source mentions no mission file). The seven per-mission
  renderers — `status.sh`, `harness-audit.sh`, `mission-tui.sh`,
  `mission-diff.sh`, `mission-checkpoint.sh`, `mission-html-report.sh` — read
  mission files directly **by design**, because they render per-feature and
  plan-vs-actual detail the fleet snapshot deliberately does not carry. What
  none of them may do any more is *decide mission state*: every one resolves it
  through `status_state`, and `tests/script-renderers.test.sh` fails the build
  if a top-level `.state` read reappears. `.features[].state` stays a direct
  read — it is an ordinary field, not the thing status-read owns.
- `.claude/skills/fleet/SKILL.md` (new) — `/fleet`, the "where is everything"
  answer across all projects.

### 1.3 — Inbox / capture surface

Borrowed from `fm-inbox.sh:1-27`, which splits four things it would be natural to
merge into one:

| Subcommand | Contract |
|---|---|
| `note` | Queue an idea durably while the orchestrator is mid-turn. Writes a record **and** appends exactly one wake. The only subcommand touching the wake queue. |
| `status` | Answers "what is happening" from durable records only. No network, **no wake** — safe to poll in a loop. |
| `ask` | One-shot side question that never touches the backlog or wake queue. *A side question must not become fleet work.* |
| `drain` | Present pending notes, ack by id. |

- `scripts/inbox.sh` (new)
- `data/inbox/` — one file per note, ack'd notes archived
- `.claude/skills/inbox/SKILL.md` (new) — `/inbox`
- SessionStart injects undrained notes
- `note`'s "one wake" has nothing to append to until Phase 4 exists. In Phase 1
  it writes the record only; §4.1 wires the wake. The contract is stated now so
  the file format does not change later.
- `ask` is `claude -p --model haiku` with no tools and no cwd context — a side
  question is cheap by construction and cannot touch state.
- settings.json allow: `Bash(./scripts/inbox.sh *)`, `Bash(./scripts/project-mode.sh *)`,
  `Bash(./scripts/snapshot.sh *)`, `Bash(./scripts/fleet.sh *)`.

`ask` is the durable form of the instinct behind the existing `/aside` skill.

### 1.4 — Knowledge routing

`AGENTS.md:262-270` routes every durable fact to its most specific owner. With
one project, `learnings/` as a single bucket is fine; with a registry, everything
silts into one pile without a routing table.

| Fact | Home |
|---|---|
| Preferences and working style | `.claude/agent-memory/orchestrator/` — already exists with six entries; **no new `captain.md`** |
| Harness-local operational facts | `learnings/` (existing taxonomy) |
| Task-scoped notes | with the mission/feature |
| Investigation findings | the scout report |
| Useful to any contributor to project X | that project's committed `AGENTS.md` |

- `protocols/knowledge-routing.md` (new)
- `.claude/agents/orchestrator.md` — the routing table as a rule
- The harness never writes a project's `AGENTS.md` directly; a worker does it
  through that project's registered delivery path.

### Verification
Register three projects across all three modes. `/fleet` shows all active work in
one view. `/inbox note` mid-turn survives a session kill and appears on drain.
Snapshot output is byte-identical across two runs on unchanged state.

---

# Phase 2 — Durable decision holds

Small and foundational: the crew (Phase 3) and the watcher (Phase 4) both need to
ask "is a human currently blocking this?" before acting.

### 2.1 — Decision holds

You already invented this by hand: `open_questions`, `user_actions` with
`status: "decided-pending-user"`, and a `decisions` map recording A1's outcome,
all hand-maintained in one `status.json`. This makes it a schema tooling can read.

One file per open decision, `missions/<id>/decisions/DH-001.json`:

```json
{
  "id": "DH-001",
  "mission_id": "2026-06-29-store-review-remediation",
  "project": "mobile-app",
  "opened_at": "2026-09-09T10:00:00Z",
  "blocking": true,
  "question": "Reword the listing, or change the store category?",
  "options": ["reword the listing", "change category"],
  "recommendation": "reword — smaller diff, no category re-review",
  "context_path": "features/003-reachability/scrutiny.md",
  "answered_at": null,
  "answer": null
}
```

- `templates/decision-hold.md`, `protocols/decision-hold.md` (new)
- `.claude/skills/decide/SKILL.md` (new) — `/decide` walks open holds across
  **all** projects, one at a time, in impact order
- `session-start-inject-status.sh` — inject open holds verbatim, first
- `stop-turnend-guard.sh` — block if normalised state is `awaiting_approval` and
  no unanswered hold exists on disk (the orchestrator asked in prose and lost it)
- `scripts/snapshot.sh` — holds become part of the fleet contract
- Rule in `protocols/orchestrator.md`: *a blocking question is not asked until it is filed.*
- **Mission approval is a hold.** The `awaiting_approval` state stops being a
  special case: `mission-start` files `DH-000` ("approve plan + contract?") and
  approval is its answer. One mechanism, one skill, one place to look.
- `blocking: false` holds are advisory: they appear in `/decide` and `/fleet`,
  but neither the crew nor the watcher waits on them.
- Answers given in prose count, but only once filed: the orchestrator writes
  `answer` before acting on it. A hold answered in chat and never filed is the
  exact loss this phase exists to prevent.
- **`PreCompact` hook** (new, `.claude/hooks/pre-compact-snapshot.sh`) — before
  context compaction, write open holds, the current feature, and the last three
  log lines to `state/precompact-<session>.md`; `UserPromptSubmit` re-injects it
  once and deletes it. Compaction is the second way a promised answer gets lost,
  after restart; the schema exists (`PreCompact` is in the settings schema) and
  this is the cheapest place to use it.
- settings.json allow: `Write(./missions/**/decisions/**)`, `Skill(decide)`.

### Verification
Open a hold, `/clear`, restart — SessionStart shows the question. Answer it,
restart — shows the answer, not the question. Open a hold, force a compaction —
the next turn still knows it. Put a mission in `awaiting_approval` with no
`DH-000` — the Stop guard blocks.

---

# Phase 3 — The crew

**The change.** A Worker stops being an in-process subagent and becomes a real
CLI process — **headless** (`claude -p`) — in its own git worktree, with a tmux
window that shows its rendered stream and lets you attach interactively when it
needs a human.

**This is not a vote for parallelism.** `serial-execution.md:3` bans concurrent
Workers for correctness — "parallelism compounds errors" — and that rule survives
intact. Crew decouples two things currently conflated: *separate process* and
*concurrent execution*. Ships with a concurrency limit of **1**. Raising it is a
later, separate decision, gated on the Phase 0 test suite and §3.6.

### Why it is worth the cost

| | in-process subagent (today) | crewmate |
|---|---|---|
| Controller during work | **blocked inside a tool call** | free — supervises, answers you, watches other projects |
| Visibility | a spinner | a live pane rendering its stream |
| Intervention | kill the mission | send a steer; attach interactively when it reports `blocked:` |
| Session dies | work is lost | worktree + ledger survive; next session reconciles |
| Context | shares the orchestrator's window | its own full window |
| Validator isolation | prompt discipline | **structural** — separate OS process |

That last row matters more than it looks. `README.md:14` promises validators
"never see the worker's reasoning"; today that holds only because the
orchestrator does not paste it. With crewmates it becomes physically true.

Two pieces of your architecture are already shaped for this: `handoff.md:3` — "the
handoff is the only artifact that crosses agent boundaries" — is already a
file-based process contract, and `protocols/parallel-worktrees.md` already
specifies worktree isolation.

### 3.0 — Spike: DONE, results in docs/verification/crew-spike.md
All four testable checks passed against Claude Code 2.1.266; (e) `no-mistakes`
could not be verified because the tool is not installed, so `[no-mistakes]`
degrades to `direct-PR` plus a filed decision. One new finding changed the
design: `--allowed-tools` / `--disallowed-tools` are **variadic** and silently
swallow a trailing positional prompt, so the launch prompt goes on **stdin**.

(b) came out better than assumed: a disallowed tool is *absent from the model's
tool list*, so `--dangerously-skip-permissions` is not needed anywhere.

### 3.0 (original) — Spike first (half a day, no production code)
The headless design below rests on five behaviours of Claude Code 2.1.x that are
documented but not yet exercised here. Verify each in a throwaway worktree
**before** writing `spawn.sh`; any failure changes the design, not the schedule.

| # | Check | If it fails |
|---|---|---|
| a | SIGINT a `-p` run mid-tool-call, then `claude --resume <id> -p "<steer>"` continues coherently | steer becomes "wait for exit, then resume" — slower, still deterministic |
| b | `-p` with `--disallowedTools` — a disallowed call returns a tool error and the run continues, no hang, no prompt | fall back to interactive + PreToolUse guards (firstmate's shape) |
| c | Hooks in the worktree's `settings.local.json` fire under `-p` (only `--bare` skips them) | ledger writes move entirely into the brief protocol |
| d | `--output-format stream-json` yields `session_id` in the init event and `usage`/`total_cost_usd` in the result event | keep `usage.sh` transcript scraping from the previous draft |
| e | The exact `no-mistakes` invocation on a pushed branch, and how its run status is read (`fm-nm-run-lib.sh` is the reference) | `[no-mistakes]` mode degrades to `direct-PR` + a hold until confirmed |

### 3.1 — Spawn
`scripts/crew/spawn.sh`, in this order, each step refusing loudly on failure:

1. `git worktree add data/worktrees/<project>/<task> -b hc/<mission>/<Fid>-<slug>`
   off the project's default branch. `trust.sh` is no longer needed — the
   workspace-trust dialog is skipped in non-interactive mode — but the same
   structural check stays: the target must be a *linked worktree of the named
   project* (own git dir, shared common dir, top level equal to the argument);
   a primary checkout, subdirectory, unrelated repo, or plain folder is refused.
2. **Inject crewmate-side hooks** by writing `<worktree>/.claude/settings.local.json`
   (`fm-spawn.sh:3228-3236`) — how the harness reaches a process in someone
   else's repo without touching that repo. `Stop` → `idle:` ledger line;
   `UserPromptSubmit` → `busy:`; `SessionEnd` → `exited:`; and one
   `PreToolUse` guard, `scripts/crew/guard-pretool.sh`, that hard-blocks
   `git push` to the project's default branch, `gh pr merge`, `git worktree`,
   and any `cd` above the worktree root. Hooks fire regardless of permission
   mode, so this guard holds even if the allowlist is misconfigured. Every hook
   command ends `|| true` so a stale writer can never break the crewmate.
3. Resolve the **tool allowlist**: a fixed base (`Read`, `Edit`, `Write`, `Glob`,
   `Grep`, `Bash(git add *)`, `Bash(git commit *)`, `Bash(git status*)`,
   `Bash(git diff*)`, `Bash(git log*)`) plus the project's registered
   `allow=` commands (§1.1 — e.g. `bun *`, `pytest *`), plus per-brief extras.
   Disallowed: `Bash(git push*)`, `Bash(gh *)`, `Bash(rm -rf*)`, `WebFetch`,
   `Agent`. In `-p` mode a disallowed call fails instead of prompting; the
   crewmate sees the error and either adapts or writes `blocked:`.
4. Launch through `scripts/crew/run.sh` (the process owner), cwd = worktree:
   ```
   claude -p --output-format stream-json --verbose \
     --model <model> --allowedTools <…> --disallowedTools <…> \
     --append-system-prompt-file templates/crew-persona.md \
     "<one line: read the brief at <abs path> and begin>"
   ```
   **No `--dangerously-skip-permissions`.** `run.sh` tees the raw stream to
   `state/<task>.stream.jsonl`, renders it human-readable to its own stdout, and
   captures `session_id` from the init event into `state/<task>.meta`.
5. Open tmux window `hc-<mission>-<Fid>` running `run.sh` so the rendered stream
   is watchable and Ctrl-C reaches the process owner. tmux is the **viewer**,
   not the transport.
6. Record `state/<task>.meta` (task, project, mission, feature, worktree, branch,
   window, pid, session_id, model, mode, yolo, started_at) and the first ledger
   line `started:`.

**Sandbox.** Three layers, none of which is skip-permissions: the worktree (a
crewmate cannot reach the primary checkout), the allowlist (anything else fails
closed under `-p`), and the PreToolUse guard (fires regardless). The delivery
mode governs **how work lands**, not what the crewmate may touch while working.

### 3.1b — `run.sh`, the process owner
One script owns the crewmate's process lifetime, so steer, exit, and resume are
one loop instead of three scripts guessing at each other:

```
launch → wait
  exit 0 + handoff present + last ledger line done:   → return 0
  exit 0 + ledger blocked:                             → leave window open with
                                                        "attach: /crew attach <task>"; return 3
  SIGUSR1 (a steer arrived)                            → SIGINT child, drain
                                                        state/<task>.inbox/*, relaunch with
                                                        --resume <session_id> -p "<steers> Continue."
  nonzero exit / no terminal ledger line               → write failed: with the
                                                        stream tail; return 1
```
Rules: a steer is never lost (written before the signal); a crewmate is never
resumed after `done:`; the window outlives the process so the last screen is
readable; `run.sh` writes `state/<task>.usage.json` from the result event on
every exit.

Borrowed guard (`fm-spawn.sh:10-14`): spawn reads the brief's recorded
`Delivery contract: mode=<mode>` and **refuses a mismatch** with its own flag, and
refuses leftover `{...}` placeholders or an empty task section. Two sources of
truth must agree or the spawn fails loudly.

### 3.2 — The brief
`scripts/crew/brief.sh` scaffolds `missions/<id>/features/<NNN>/brief.md` from
`templates/crew-brief.md`. **The brief is the worker persona now.**
`.claude/agents/worker.md` cannot load in a foreign cwd, so its Hard rules and
handoff format move into the template verbatim; the agent file stays as the
in-process fallback until Phase 5 retires it. Sections, with the split from
`fm-brief.sh:5-10`:

- `## Captain's intent` — your actual ask, plus the context needed to read it
  (the substance of any report, decision, or PR it refers to).
- `## Harness spec` — build instructions. **Never** the captain's intent.
- `## Delivery contract` — `mode=`, `yolo=`, `model=` (default from
  `status.json.models.worker_default`; a mechanical feature can name `haiku`, a
  hard one `opus`, without touching the protocol), cross-checked by spawn.
- `## Definition of done` — the feature's slice of the validation contract.
- `## Protocol` — absolute paths to the ledger and handoff, the exact ledger
  vocabulary, and the rule that the last thing a crewmate does is write `done:`
  or `failed:` *then* stop. Never ends its own session.

Splitting intent from spec lets a crewmate return a SPEC-CLARIFICATION handoff
(`handoff.md:20`) against the *how* without discarding the *why*.

### 3.3 — Supervision channel
- `scripts/crew/peek.sh <task> [lines=40]` — bounded pane tail for cheap
  diagnosis. Bounded by default so a peek can never blow the context window.
- `scripts/crew/send.sh <task> <text>` — **two data planes** (`fm-send.sh:16-19`),
  made deterministic: write the steer to `state/<task>.inbox/<ts>.md`, *then*
  `SIGUSR1` the `run.sh` pid from `.meta`. `run.sh` does the interrupt-and-resume
  (§3.1b). No keystrokes, no composer guessing. Refuses an unresolved target;
  never falls back to a window search.
- `scripts/crew/attach.sh <task>` — the human rescue: in the crewmate's window,
  `claude --resume <session_id>` interactively in its worktree. Available once
  `run.sh` has exited (`blocked:` or `failed:`); refused while it is running.
  When you detach, the orchestrator re-briefs from the handoff, not from your
  transcript.
- `state/<task>.ledger` — append-only status lines the crewmate writes
  (`started:`, `progress:`, `blocked:`, `done:`, `failed:`). This is the contract
  the supervisor and the §4.1 watcher both read.

### 3.3b — Where validation sits
The worktree **persists through validation**. Validators stay in-process
subagents of the orchestrator — they are read-only, adversarial, and short — and
run against the worktree (`cd` in their Bash calls; the spawn prompt carries the
path). They receive the diff and the handoff, nothing else; the crewmate's pane
and context are physically out of reach. A red verdict does **not** tear down:
the orchestrator appends a `## Followup` section to the same brief and `send.sh`
nudges the same crewmate on the same branch — a followup is a re-brief, not a
respawn. Teardown happens only after green, or on abandon.

### 3.3c — Token and cost accounting
`SubagentStop` never fires for a crewmate. `run.sh` writes
`state/<task>.usage.json` (input, output, cache, `total_cost_usd`, model) from
the stream-json result event on every exit — one source, no transcript scraping.
Teardown folds it into `status.json.tokens.workers` and the snapshot's spend
roll-up (§1.2). Validators keep the existing `SubagentStop` path.

### 3.4 — Reconcile
`scripts/crew/reconcile.sh` at SessionStart. **Ledger-first**
(`fm-inactive-reconcile.sh:14-17`): a task whose ledger ends in a whole `done:` or
`failed:` line has stated its own outcome — trust that before probing the process.
Then: live window + live pid → adopt; dead window, no terminal ledger line →
report as suspicious-inactive, never silently mark failed.

### 3.5 — Teardown and ship
`scripts/crew/teardown.sh` — refuse if `.meta` says `run.sh` is alive; then land
the outcome and ship under the project's registered mode from §1.1:

- `no-mistakes` → push the branch and hand it to the **`no-mistakes` tool** — the
  gate pipeline you already run (review / fix / document / test / lint / pr /
  rebase / ci). Division of labour: harness validators answer *does it meet the
  contract*; no-mistakes answers *is it mergeable*. `pr-poll.sh` polls the
  no-mistakes run and CI. The harness repo itself gets a `.no-mistakes.yaml`
  with `disable_project_settings: true`, as firstmate's has, so a gate agent
  never adopts the orchestrator identity.
- `direct-PR` → push + `gh pr create`; `pr-poll.sh` watches CI.
- `local-only` → guarded fast-forward merge into the default branch of the
  primary checkout, refused if that branch has moved.

`+yolo` is the only path that merges unattended; otherwise a green PR files a
hold. **Git hygiene, every path:** after landing, delete the `hc/*` branch
locally and on origin if pushed, `git worktree remove`, then `git worktree prune`
in the primary checkout. Nothing accumulates in the project.

**Write-ahead intent** (`fm-teardown.sh:9-17`): the completion links (PR URL,
report path) live only in the record being removed, so the intended transition is
written to `state/<task>.close-pending` **first**. A process killed mid-teardown
leaves the next SessionStart enough to finish it. A failed transition is loud,
preserves its pending record, and is retried — never silently dropped.

Absorbs the old Phase 3.1: `scripts/pr-poll.sh` is the CI-watching half of this,
and gives §4.1 its first genuinely *external* event to park on.

### 3.6 — Concurrency, deliberately last
`missions/<id>/status.json` gains `execution: "crew"` (recorded at intake;
missions already `executing` at cutover keep `"subagent"` and finish under the
old worker — no mission changes model mid-flight) and `crew: { "max_concurrent": 1 }`.
`spawn.sh` counts live `state/*.meta` and refuses to exceed it;
`pre-agent-spawn-serial.sh` keeps guarding in-process spawns unchanged. Raising it above 1 requires the Phase 1.1 registry (to scope
worktrees per project), Phase 2 holds (to escalate collisions), and §5.3 leases
(to arbitrate a shared repo). Until then the crew runs exactly as serially as
today — it is just visible, steerable, and survivable.

### 3.7 — Scouts as crew
Investigations are the longest-blocking thing the orchestrator does in-process.
A scout is a brief with `## Report` in place of `## Definition of done`
(`templates/crew-brief-scout.md`), a read-only allowlist plus `Write` to the
report path only, and a teardown that copies the report to
`missions/<id>/reports/` and deletes the branch — no merge, no PR.
`.claude/agents/scout.md` stays as the in-process option for short questions.

### Blast radius
The worktree **is** the sandbox, enforced three ways: the tool allowlist under
`-p` (§3.1 step 3), the PreToolUse guard that fires regardless of permission
mode (§3.1 step 2), and the fact that a crewmate never merges — the supervisor
does, under the registered mode. `+yolo` changes nothing about the crewmate; it
only lets the supervisor merge unattended.

### Testing tmux-dependent code
`HARNESS_CREW_BACKEND=fake` selects `scripts/crew/backend-fake.sh`, which records
every call to a log file instead of touching tmux; CI runs the whole crew suite
against it. A `tests/run.sh --real-tmux` lane exists for local runs only and is
never required for green.

### Files
`scripts/crew/{spawn,run,brief,peek,send,attach,guard-pretool,reconcile,teardown}.sh`,
`scripts/crew/backend-tmux.sh` and `backend-fake.sh` (the viewer adapter,
per `backends/tmux.sh:4-9`), `scripts/pr-poll.sh`, `templates/crew-persona.md`,
`templates/crew-brief.md`, `templates/crew-brief-scout.md`, `.no-mistakes.yaml`,
`protocols/crew.md`, `.claude/skills/crew/SKILL.md`
(`/crew list|peek|send|attach|kill`),
`.claude/agents/orchestrator.md` + `protocols/orchestrator.md` (the crew
lifecycle as procedure), `protocols/worker.md` (now describes the brief),
`protocols/serial-execution.md` (amended: the ban is on concurrency, not on
process isolation). settings.json allow: `Bash(./scripts/crew/*)`,
`Bash(./scripts/pr-poll.sh *)`, `Bash(git worktree list*)`, `Skill(crew)`.

Realistic size: **~800 lines of new bash**, against firstmate's ~9,000 — the
difference is headless-only (no composer/busy detection, no trust dance), tmux as
viewer only, no secondmates, no remote homes, no quota routing.
This is the largest phase and the one that changes how every mission runs.

### Verification
Spike table green first. Then one mission end-to-end as crew: watch the pane,
steer it mid-feature with `send.sh` and confirm the resume is coherent, force a
`blocked:` and rescue it with `attach.sh`, kill the supervisor session mid-feature
and confirm the next session reconciles, confirm the validator receives only diff
+ handoff, confirm a disallowed `git push` fails closed, confirm teardown survives
a `kill -9` between push and worktree-removal, and confirm the project has no
leftover `hc/*` branch or worktree entry afterwards. One scout mission end-to-end.

---

# Phase 4 — Continuity

### 4.1 — Tokenless continuity (`asyncRewake` watcher)

firstmate registers a second Stop hook with `"asyncRewake": true, "timeout": 28800`.
Claude fires it in the background; it parks on a sleep loop, and on an actionable
event prints to **stderr** and exits **2** — delivered as "Stop hook feedback",
waking an idle session. Zero tokens while parked.

Because Phase 3 makes crewmates real processes, nearly every wake is an
**event** (a ledger line, a PR state change, a stall). The remaining case — the
orchestrator ended its turn with an obvious agent-owned next step and nothing in
flight — is an orchestrator *mistake*, and the right fix is to refuse that stop,
not to resume it on a timer.

**4.0 — The turn-end guard is primary.** `stop-turnend-guard.sh` becomes
`stop-turnend-guard.sh` and gains one rule: block (exit 2, reason on stderr)
when a mission is `executing`, no crewmate is live, no blocking hold is open,
and a feature is pending — "you ended blind; dispatch F003, or set `paused`, or
file a hold." Loop safety as firstmate's: after 3 consecutive blocks on the same
epoch it fails open with one notification. The continuation wake below is then
only the backstop for that fail-open, with a **5-minute** grace, not 45 s.

| Condition | Behaviour |
|---|---|
| A crewmate wrote `done:`/`failed:`/`blocked:` to its ledger, or a polled PR changed state | **Event wake.** Exit 2 naming the task and outcome |
| Guard failed open on an `executing` mission with an agent-owned next action | **Continuation wake (backstop).** 5-min grace, then exit 2 with `resume — <project>/<mission> <F-id> <next action>` |
| Crewmate live but silent past its stall threshold (no ledger write > 20 min) | **Stall wake.** Exit 2; the supervisor peeks before deciding |
| Open decision hold, or `awaiting_approval` | **Never wake.** Exit 0 silently. §4.2 owns the nagging |

**Preconditions, verified:** `asyncRewake`, `UserPromptSubmit`, `PreCompact`, and
`SessionEnd` are all present in the current Claude Code settings schema; the
installed CLI is 2.1.266. Two gotchas from `docs/turnend-guard.md:93-96`:
Claude sets `stop_hook_active=true` on every stop after *any* continuation,
including an `asyncRewake` rewake — a synchronous guard that reads that flag as
"already continued once, allow the stop" goes blind exactly when it matters, so
the guard ignores it. And the async hook must never run under a harness that
lacks `asyncRewake` (it would hold the turn open for the full timeout), so it
exits 0 unless the payload is Claude's.

**Pause semantics — the wake that must not happen.** "Stop, I'll take over" ends
a turn; without a rule the guard blocks it and the backstop resumes it. So: the watcher
continuation-wakes **only on normalised `executing`**, and the orchestrator sets
`paused` before ending any turn in which the captain asked it to stop. `/pause`
and `/resume` (new, tiny) make that a one-word gesture; the rule lives in
`protocols/orchestrator.md`.

**Files:** `scripts/watch.sh` (park loop), `.claude/hooks/stop-watch-rearm.sh`
(scope + identity + single-flight, then runs the loop in the **foreground** of the
hook's process tree — never `&`, so Claude's teardown kills it),
`.claude/hooks/user-prompt-restore.sh` (one hook, two jobs: restore the
  pre-compaction carry and clear the watcher epoch — both mean "the captain
  spoke", and splitting them would give that fact two owners), `.claude/skills/{pause,resume}/SKILL.md`,
`.claude/settings.json`, `protocols/continuity.md`. settings.json allow:
`Bash(./scripts/watch.sh *)`, `Skill(pause)`, `Skill(resume)`.

**Rails — the part that can burn money if wrong:**
- Identity: arms only when the hook payload's `session_id` matches
  `state/session.lock` (§0.3). A second session never arms or rewakes.
- Bounded auto-continuation: `state/watch-epoch` counts consecutive
  continuation wakes per mission; cap `HARNESS_MAX_AUTO_CONTINUE=10` (lower than
  the previous draft — with the guard primary, a healthy loop rarely needs any). At the cap,
  one notification, then exit 0 until reset.
- A `UserPromptSubmit` hook clears the epoch — any real message means attended.
- Scope guard: arms only when `$CLAUDE_PROJECT_DIR` holds `missions/` *and*
  `.claude/agents/orchestrator.md`. Worktrees and other repos stay inert.
- Single-flight: `state/watch.lock` holds a pid; a firing finding a live owner
  (`kill -0`) exits 0. (firstmate's epoch-generation ledger solves multi-home
  contention we do not have.)
- Absolute cap `HARNESS_MAX_PARK=28800`. Kill switch `touch state/.watch-off`.
- Never writes stdout. Exit 0 always silent.

### Verification (4.1)
Fixture × each row of the table, asserting exit code and stderr. Live: a
two-feature crew mission advances F001 → F002 with no human turn; say "pause" and
confirm no wake for 10 min; send a message and confirm the epoch resets; drive
the epoch to 25 and confirm exactly one notification and silence after.

### 4.2 — AFK mode + wedge alarm

`/afk` hands the watcher to a bash sub-supervisor that batches routine events into
a digest and escalates only captain-relevant ones. The part worth stealing is the
**wedge alarm** (`docs/wedge-alarm.md`): it defends against *the escalation itself
going nowhere*, not against idleness.

- While `state/.afk` exists the §4.1 watcher never continuation-wakes — AFK owns
  the watcher (firstmate's rule) — it only appends to the digest.
- Escalations write an ack file. No ack after `HARNESS_WEDGE_MINUTES` (default 30)
  → escalating ladder: Notification Center → Slack webhook → terminal bell,
  repeating every 10 min.
- `scripts/notify.sh` (new) — the ladder, extracted from the existing
  platform/Slack/email block at `notify-at-gate.sh:60-104`; that hook becomes a
  thin caller so both paths share one implementation.
- `/afk return` presents the digest, then drops into `/decide` if holds are open.
- `.claude/skills/afk/SKILL.md`, `scripts/afk.sh`, `protocols/afk.md`,
  `docs/wedge-alarm.md` (new). settings.json allow: `Bash(./scripts/afk.sh *)`,
  `Bash(./scripts/notify.sh *)`, `Skill(afk)`.

### Verification (4.2)
Enter AFK, force a blocking hold, `HARNESS_WEDGE_MINUTES=1`, confirm the ladder
escalates and that writing the ack file stops it. Kill the AFK daemon and confirm
the next SessionStart notices the expired `.afk` and presents the digest anyway.

---

# Phase 5 — Knowledge lifecycle and hardening

### 5.1 — `/stow` lifecycle for `learnings/`

`learnings/` has taxonomy, frontmatter, and a regenerating `INDEX.md`. What it has
no concept of is **age**: 13 entries, nothing ages out, nothing caps growth, and
all of it loads into planning forever.

- Additive frontmatter: `last_referenced`, `reference_count`, `tier: hot|warm|cold`
- hot = referenced in the last 3 missions; warm = has a recurrence log entry;
  cold = neither and older than 60 days
- `learnings/archive/` — cold entries move here; `INDEX.md` keeps a one-line stub
- Budget `HARNESS_LEARNINGS_BUDGET` (default 40 active). Over budget → **propose**
  the coldest N and ask. Never auto-delete.
- Anti-patterns are exempt from auto-archival: a trap you stopped hitting is
  exactly the one you are about to hit again.
- `.claude/skills/stow/SKILL.md`, `scripts/learnings-curate.sh` (new);
  `learnings-index.sh` gains tier and `last_referenced` columns.

Routes through §1.4 — `/stow` files each finding to its correct owner, not
just into `learnings/`.

Verification: backdate fixture entries, run curate, confirm tiering, confirm
archival is proposed not performed, and that `INDEX.md` is byte-identical on a
second run (its existing idempotence guarantee).

---

### 5.2 — Startup memory budget
`config/startup-memory-budget`, default 7,500 estimated tokens, accounted **before**
injection. Today `session-start-inject-status.sh` injects unbounded log tails;
multiplied by a projects registry, every session starts heavy.
- `scripts/memory-budget.sh` (new); SessionStart truncates to fit and says so.

### 5.3 — Lease discipline
Named leases per resource (actor + pid + staleness), replacing the single serial
spawn lock. Needed the moment two missions target one repo.
- `scripts/lease.sh` (new); `pre-agent-spawn-serial.sh` and `crew/spawn.sh` both
  migrate onto it, so in-process and crew spawns share one arbiter.

### 5.4 — Retire the in-process worker — WITHDRAWN
The original condition ("once every mission recording `execution: subagent` is
closed") was **vacuous**: nothing ever set `execution` at all, so it could never
fire, and both paths would have lived forever with no way to tell which was
real.

It is also the wrong goal. The subagent path is the correct fallback for a
project that is not registered, and `feature-dispatch.sh` selects between the
two deliberately. `protocols/worker.md` now states its scope in its first
paragraph. Two documented models beat one model and one ghost.

### 5.5 — Fleet dashboard (optional)
`scripts/fleet-html.sh` renders the §1.2 snapshot to one static page — projects,
active crew, open holds, spend by day — and replaces `mission-html-report.sh`.
Trivial once the snapshot exists; deliberately last.

---

## Estimate

| Phase | Build | Notes |
|---|---|---|
| 0 | 1–1.5 days | tests for 8 hooks, lock, doctor, CI |
| 1 | 1.5 days | registry, snapshot + 6 renderer migrations, inbox |
| 2 | 0.5 day | holds + PreCompact |
| 3 | 5–6 days | **half a day of spike first**; expect a second pass after living with it |
| 4 | 2 days | guard rewrite, watcher, AFK, notify ladder |
| 5 | 2 days | stow, budget, leases, dashboard |

Roughly three weeks with a review at every phase boundary. Phases 0–2 are a
clean resting point that already makes the harness multi-project aware.

## Build order

Phase 0 → 1 → 2 → 3 → 4 → 5, in order. Each phase is independently useful and
independently revertible; nothing after Phase 2 is required for the harness to
keep working exactly as it does today.

The one ordering that is not negotiable: **holds (2) before crew (3) before
watcher (4)**. Crew needs somewhere to escalate; the watcher must be able to ask
"is a human blocking this?" before it self-continues.

## Explicitly out of scope
secondmates · Relay (X/Discord) · the seven-harness adapter layer · remote homes ·
voice relay · any session backend other than tmux (herdr/zellij/orca/cmux) · quota-array dispatch
(`fm-quota-choose.sh` is 408 lines to answer what `model-routing.md` answers) ·
self-update · doc-audience-check · firstmate's `.mjs` command-policy engine (one
bash PreToolUse guard is in scope, §3.1) · interactive-pane crewmates as the
default transport · concurrent crewmates (§3.6 ships the limit at 1; raising it
is a later decision)

## Rollback
Every behavioral mechanism is inert without its `settings.json` entry; the watcher
additionally has `state/.watch-off`. Phase 0 and the snapshot layer are
read-path only. Phase 3 is reversible per mission — intake records
`execution: "subagent"` and the old path runs untouched until §5.4. No existing
mission file is rewritten by any phase; new fields are additive.

## Review log
- **2026-09-09, issue review.** Crewmates go **headless** (`claude -p`,
  stream-json, `--resume`) with tmux as viewer only — removes the trust dance,
  composer/keystroke steering, and transcript scraping; `run.sh` owns the
  process loop; `attach.sh` is the human rescue. Sandbox rebuilt on the `-p`
  allowlist plus one PreToolUse guard, **no skip-permissions** (a `permissions.deny`
  under skip-permissions was decorative). Added: §3.0 spike table; §0.3 session
  lock with observer mode and `session_id` identity in every acting hook; §4.0
  turn-end guard as primary with continuation wake demoted to a 5-min backstop
  and the cap lowered to 10; `[no-mistakes]` mode now invokes the no-mistakes
  tool with a stated division of labour, plus `.no-mistakes.yaml` for the harness
  itself; branch/worktree hygiene in teardown and doctor; scouts as crew (§3.7);
  spend in the snapshot with an optional daily cap; `model=` per brief; optional
  dashboard (§5.5); an estimate table.
- **2026-09-09, gap review.** Added: layout/state roots; `doctor.sh`; registry
  paths + worktree location; snapshot timing budget; inbox wake timing and `ask`
  mechanics; reconciled `captain.md` with existing agent-memory; approval-as-hold,
  advisory holds, `PreCompact` snapshot; crew launch mechanics (trust
  pre-registration, injected `settings.local.json` hooks and deny list, skip-
  permissions rationale), brief-as-persona, validation placement, followup as
  re-brief, crewmate token accounting, fake backend for tests, per-mission
  migration flag; watcher preconditions, `stop_hook_active` gotcha, pause
  semantics; per-phase settings.json allow entries; verification for Phases 2, 4,
  5; worker.md retirement; fixed the tmux out-of-scope contradiction and the
  stale §0.2 reference.
