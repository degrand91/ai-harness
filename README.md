# Harness

An autonomous coding harness that runs on top of Claude Code, and a control plane for the projects it works on.

**Goal.** You define **what**. The harness handles **how** — for hours, days, or weeks — and asks you only about things that are genuinely yours to decide.

## What it is

Open a Claude Code session in this folder and that session **is** the Orchestrator (`.claude/settings.json: agent`). It plans, dispatches, validates, decides and remembers. It does not write your project code — crewmates do that, in their own worktrees, and the Orchestrator lands their work under each project's registered delivery mode.

| Role | Runs as | Job |
|---|---|---|
| **Orchestrator** | your session | plans features, writes the **validation contract** before any code, dispatches, decides, ships |
| **Crewmate** | its own headless `claude -p` process, in its own git worktree | implements exactly one brief, commits, reports, stops |
| **Validators** | in-process subagents | adversarial by design — they see the diff and the handoff, never the crewmate's reasoning |

Crewmates are separate OS processes, so the Orchestrator is **not blocked while work happens**. That is what makes it a control plane rather than a tool that runs one thing at a time.

**This is not parallelism.** `crew.max_concurrent` ships at **1**, and [`protocols/serial-execution.md`](protocols/serial-execution.md) explains why: correctness compounds over multi-day runs, parallelism compounds errors. Crew separates *"its own process"* from *"at the same time"* — only the first is new.

## Quickstart

```sh
./scripts/doctor.sh                 # check tools, create local state roots
claude                              # the session is the Orchestrator

# register the projects this harness delivers to
./scripts/project.sh add myapp ~/projects/myapp --mode no-mistakes --allow "bun *"

# then, in the session:
/mission-start Add OAuth login to myapp
```

The plan and contract are drafted through conversation, and approval is the one mandatory human gate — recorded as a decision on disk (`DH-000`), not as a chat turn that a restart could lose.

## Living with it

```sh
./scripts/fleet.sh                  # everything in flight, across all projects
./scripts/crew/reconcile.sh         # what happened to every crewmate
./scripts/crew/peek.sh F001         # bounded look at one crewmate
./scripts/crew/send.sh F001 "use the retry helper"
./scripts/hold.sh list              # decisions waiting on you
./scripts/inbox.sh note "check the flaky login test"
```

Slash-skills for the same, in-session: `/fleet` `/crew` `/decide` `/inbox` `/project` `/afk` `/pause` `/resume` `/stow`, plus the mission set (`/mission-start`, `/mission-status`, `/mission-resume`, `/mission-list`, `/mission-review`).

Everything is a file. Kill the session at any point; the next one reconciles from disk.

## The five ideas that matter

**1. One owner per fact.** `scripts/lib/status-read.sh` is the only thing that decides a mission's state; `snapshot.sh` is the only thing that reads fleet state; `registry.sh` owns the project registry. Six renderers each parsing `status.json` independently is how a schema drift went unnoticed in all six at once.

**2. A question to you is a file, not a turn.** A question asked in chat is erased by a restart or a context compaction, and you get asked it twice — which is how you stop trusting the queue. Decisions live in `missions/<id>/decisions/`, are injected first at session start, and are carried across compaction. See [`protocols/decision-hold.md`](protocols/decision-hold.md).

**3. The ledger is the contract.** A crewmate writes `progress:`, `blocked:`, `done:` or `failed:` to its own append-only ledger, through hooks injected into its worktree. A supervisor that died mid-flight reconstructs the outcome from disk alone. `blocked` is deliberately **not** terminal — a blocked crewmate is waiting, not finished.

**4. Refuse rather than resume.** The turn-end guard blocks a stop that ends the loop for no reason; the `asyncRewake` watcher parks on fleet state and wakes on real events, at zero token cost. Both stop dead for an open decision, a paused mission, or away mode. See [`protocols/continuity.md`](protocols/continuity.md).

**5. Rails that fire forever get switched off.** Every guard is bounded — a recency window, a retry cap, a fail-open. A guard that can refuse forever is a wedged session, which is worse than the thing it was guarding against.

## The sandbox

A crewmate is contained three ways, none of them `--dangerously-skip-permissions`:

1. **Its worktree** — it cannot reach the project's primary checkout.
2. **The `-p` tool allowlist** — a disallowed tool is *absent from its tool list*, so it never attempts the call. The base set plus the project's registered `allow=` commands, and nothing else.
3. **An injected `PreToolUse` guard** — fires regardless of permission mode, refusing `git push`, `gh pr merge`, `git worktree` and friends.

A crewmate never lands its own work. The Orchestrator does, under the mode recorded at spawn.

## Delivery modes

Registered per project in `data/projects.md`:

| Mode | Delivery |
|---|---|
| `no-mistakes` | push → PR → the `no-mistakes` gate → merge authority |
| `direct-PR` | push + PR, no gate pipeline |
| `local-only` | local branch, guarded fast-forward merge, never a remote |

`+yolo` grants merge autonomy to the **supervisor**; it changes nothing about what a crewmate may do. The registry records *the posture you registered*, never *how a given task ships* — so a task can deviate in the open instead of silently rewriting your standing policy.

## What's inside

| Path | Purpose |
|---|---|
| [CLAUDE.md](CLAUDE.md) | Operating manual every session reads on entry |
| [ARCHITECTURE.md](ARCHITECTURE.md) | The roles, strategies and state model |
| [protocols/](protocols/) | The contracts: crew, continuity, decision holds, serial execution, knowledge routing, project registry, afk |
| `.claude/agents/` | orchestrator, validators, explorer, scout |
| `.claude/skills/` | the slash-skills listed above |
| `.claude/hooks/` | session lock, status injection, turn-end guard, watcher re-arm, compaction carry, spawn serialisation |
| `scripts/` | `doctor` `project` `snapshot` `fleet` `inbox` `hold` `watch` `afk` `notify` `lease` `memory-budget` `learnings-curate` |
| `scripts/crew/` | `brief` `spawn` `run` `say` `peek` `send` `attach` `reconcile` `teardown` + backends |
| `scripts/lib/` | single owners: `status-read` `registry` `holds` `crew` `session-lock` |
| `tests/` | dependency-free suite — `bash`, `jq`, coreutils, no framework |
| `missions/` · `data/` · `state/` · `config/` | local state, all gitignored |
| `learnings/` | patterns, anti-patterns, proposals — with a lifecycle |
| [docs/verification/](docs/verification/) | what was actually proven, and how |

## Local state

Four roots, none of them tracked:

| Root | Holds |
|---|---|
| `missions/` | specs, contracts, features, handoffs, decisions |
| `data/` | project registry, inbox, crew worktrees |
| `state/` | task meta and ledgers, locks, epochs, digests |
| `config/` | your choices: budgets, thresholds, wedge timings |

## Testing

```sh
./tests/run.sh              # 26 files, ~354 assertions
./scripts/lint.sh           # shellcheck
./scripts/harness-audit.sh  # repo self-check
```

No framework: `bash`, `jq` and coreutils are all the harness itself requires, so they are all the suite may require. CI runs on Ubuntu and macOS — **macOS ships bash 3.2**, and that difference has caught real bugs. Any change under `scripts/` or `.claude/hooks/` ships a test; see [CONTRIBUTING.md](CONTRIBUTING.md).

## Status

Phases 0–5 complete. The crew path has been run end to end against a real model, through both the tmux backend and directly; `docs/verification/crew-spike.md` records which Claude Code behaviours it depends on and how they were checked.

Known gaps: the `no-mistakes` gate is unverified here (that mode degrades to `direct-PR` plus a filed decision until the tool is installed), and concurrency above 1 is deliberately unimplemented.

## Contributing and License

Contributions welcome — read [CONTRIBUTING.md](CONTRIBUTING.md) first, in particular the dog-food rule and the test rule.

MIT — see [LICENSE](LICENSE). Community standards: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Security: [SECURITY.md](SECURITY.md).

Built on insights from ECC ([affaan-m/ECC](https://github.com/affaan-m/ECC), MIT). See [docs/credits.md](docs/credits.md).
