# Protocol: The Feature Loop

How one feature goes from `pending` to `closed`. This is the single owner of that question; [lifecycle.md](lifecycle.md) owns the mission-level states around it.

---

## Two execution models

A mission records **`execution`** in `status.json` at intake and never changes it. A mission that switches model half way through is one nobody can reason about afterwards.

| | `crew` | `subagent` |
|---|---|---|
| The worker is | a headless `claude -p` process in its own git worktree | an in-process `Agent` call |
| The orchestrator during work | **free** — it can answer you, watch other projects, decide | **free** — the subagent runs in the background; the orchestrator ends its turn and is woken by the completion notification (never by polling) |
| Requires | the `target_repo` to be a **registered project** | nothing |
| Dispatched by | `scripts/feature-dispatch.sh` end to end | `feature-dispatch.sh` prints the spec; **you** call the Agent tool |
| Survives a session death | yes — worktree and ledger reconcile | no |

**The default is decided by registration.** Registering a project is your explicit act and carries the delivery posture the crew needs, so a registered `target_repo` means `crew` and an unregistered one means `subagent`. `feature-dispatch.sh` resolves it once, records it, and honours it thereafter.

## The loop

```
                 ┌─ blocking decision open? ──► stop. /decide.
                 │
pending ─────────┼─► dispatch ──► in_progress ──► outcome ──┬─ done ────► validate ──┬─ green ─► teardown ─► closed
                 │   (feature-dispatch.sh)                  │                        └─ red ───► re-brief (followup)
                 │                                          ├─ blocked ─► file a decision, then steer
                 └─ concurrency limit reached? ──► wait     └─ failed ──► read the handoff; re-brief or abandon
```

### Dispatch

```sh
./scripts/feature-dispatch.sh <mission> <feature> \
  --intent <file|-> --done <file|-> [--spec <file|->] [--model <name>] [--dry-run]
```

It refuses, rather than proceeding, when: the mission is not `executing`, a **blocking decision is open**, the feature is not `pending`, the concurrency limit is reached, or `execution: crew` but the project is not registered. Each refusal names what to do instead.

`--intent` and `--done` are required for a crew dispatch. A crewmate that does not know **why** cannot push back on **how**, and without a definition of done it will decide for itself when it is finished.

### The outcome comes from the crewmate

Never from the process. Read `crew_outcome` — `done`, `failed` or `blocked` — which ignores the `idle:`/`exited:` lines the lifecycle hooks append afterwards. `blocked` is **not** terminal: file the decision, get an answer, then `crew/send.sh` the answer. Do not tear down.

### Validation runs against the live worktree

The worktree **persists through validation**. Validators stay in-process subagents of the orchestrator — read-only, adversarial, short — and are given the **diff and the handoff only**. Scrutiny and User-Testing for the same feature are spawned **together**; their verdicts are written to the feature folder by the `SubagentStop` hook. Because a crewmate is a separate process, its reasoning is physically out of reach, which turns a convention into a guarantee.

Point the validator at `crew_meta_get <home> <task> worktree`. Do not tear down first: teardown removes the very thing being validated.

### Red is a re-brief, not a respawn

Append a `## Followup` section to the same brief and steer the same crewmate on the same branch. It has the context; a fresh one would rediscover it. Respawn only when the crewmate has gone off the rails badly enough that its context is a liability.

### Teardown

Only after green, or deliberately with `--abandon`. It writes its intent to `state/<task>.close-pending` first, lands under the mode recorded at spawn, removes the worktree and branch, folds the crewmate's token and cost usage into the mission, and forgets the task.

A failed delivery **keeps** its pending record and its worktree, and is retried.

## Throughput rules (both execution models)

Measured on `2026-10-02-overlay-replay-review`: 7.5 h from approval to the first build, of which more than half was waste. One `git push` stalled for 146 min on a flaky HTTPS link, the other pushes took 3 to 7 min each, two validators hit their turn limit after 54 min and returned nothing, and two follow-ups came from specs that left out real constraints. The rules below remove each cause.

1. **Worktrees, not clones.** For each feature the orchestrator runs `git -C <checkout> fetch` and `git worktree add --detach <dir> <base>` (or `-b <branch>`), installs dependencies once, and gives the worker that path. Workers commit there and never clone. Validators read the same commit (a second detached worktree if they need to run anything). Remove the worktrees after the feature closes.
2. **Workers never push; the orchestrator pushes once per feature** with `scripts/safe-push.sh <dir> origin <refspec>`, which aborts a stalled transfer and bounds every attempt. A failed push is not a failed feature: the commit is local, retry later.
3. **Nobody blocks on CI.** Workers and validators do not run `gh run watch`. The orchestrator starts one background watch per pushed head and records the result; a red CI opens a follow-up like any other red.
4. **Validator prompts carry a budget and a ready environment.** Scrutiny: a tool-call budget (default 35) and the worktree path. User testing: the orchestrator starts the app itself and hands over a URL, at most 3 steps, about 30 tool calls, and the interaction model quoted from the implementation. Both agents must write a verdict before the budget runs out (see their role files).
5. **Independent features run in parallel only through `crew`.** In-process workers stay serial (the serial-spawn hook enforces it, and [parallel-worktrees.md](parallel-worktrees.md) is superseded). When a mission has features that touch disjoint files and do not need each other's output (e.g. a release-workflow change and a new runtime module), say so at intake and ask the captain whether to register the project: a registered `target_repo` runs as `crew`, where each feature is its own process in its own worktree under the concurrency limit. Registration is the captain's call, never the orchestrator's.
6. **Specs state the real constraints up front:** who uses the output and on which platform (a portable build for a Windows tester), and fixtures captured from the real system **with exactly the options the feature sends**. Both of the measured follow-ups were missing one of these.

## Advancing

Set the feature `closed`/`green`, then dispatch the next `pending` one. When none remain, move the mission to `closing` and run the full contract end to end.

**Do not end a turn with a pending feature, nothing in flight, and nobody waiting on the captain.** The turn-end guard refuses it and tells you your three options: dispatch, file the decision you actually need, or `/pause`. See [continuity.md](continuity.md).
