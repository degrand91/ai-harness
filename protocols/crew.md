# Protocol: The Crew

A Worker is not a subagent. It is a **headless `claude -p` process**, in its own
git worktree, owned by `scripts/crew/run.sh`, watched through a window you can
read and interrupt.

---

## Why this shape

With in-process subagents the orchestrator is **blocked inside a tool call** for
the entire duration of any work it dispatches. A control plane that cannot
answer you while work is happening is not a control plane. Everything else here
follows from removing that.

| | in-process subagent | crewmate |
|---|---|---|
| Controller during work | blocked in a tool call | free |
| Visibility | a spinner | a window rendering its stream |
| Intervention | kill the mission | steer it, or attach when it blocks |
| Session dies | work is lost | worktree + ledger survive; reconcile resumes |
| Context | shares the orchestrator's | its own |
| Validator isolation | prompt discipline | **structural** — a separate process |

That last row matters more than it looks. `README.md` promises validators "never
see the worker's reasoning". As subagents that held only because the
orchestrator did not paste it. As separate processes it is physically true.

## This is not a vote for parallelism

[serial-execution.md](serial-execution.md) bans concurrent Workers for
correctness, and that rule is untouched. Crew separates two things that were
conflated: **its own process** and **at the same time**. Only the first is new.
`crew.max_concurrent` ships at **1**; raising it is a separate, deliberate
decision.

## The lifecycle

```
brief.sh    render the brief (intent | spec | done | delivery contract)
spawn.sh    worktree -> inject hooks -> resolve allowlist -> meta -> window
run.sh      own the process: launch, steer, resume, absorb usage, report
send.sh     write the steer, then SIGUSR1 the runner
peek.sh     bounded ledger + window tail
attach.sh   resume the crewmate's own session by hand, once it has stopped
reconcile.sh  ledger first, then process liveness
teardown.sh   write-ahead intent -> land -> remove worktree -> forget
```

## The ledger is the contract

`state/<task>.ledger` is append-only and written by the **crewmate's own
process**, through hooks injected into its worktree. A supervisor that died
mid-flight reconstructs the outcome from disk alone.

| verb | meaning |
|---|---|
| `started:` | worktree and process exist |
| `busy:` / `idle:` | a turn began / ended (`UserPromptSubmit` / `Stop` hooks) |
| `progress:` | a self-reported milestone |
| `blocked:` | waiting on a human — **not terminal** |
| `done:` / `failed:` | **terminal** |
| `exited:` | the process ended (`SessionEnd` hook) |

`blocked` is deliberately not terminal: a blocked crewmate is waiting, not
finished, and tearing its worktree down would discard the work that got it
there. Only a **complete** final line counts — a process killed mid-write leaves
a partial line, and reading it would invent a `done` that never happened.

## The sandbox is three layers

None of them is `--dangerously-skip-permissions`.

1. **The worktree.** A crewmate cannot reach the primary checkout.
2. **The `-p` allowlist.** A disallowed tool is *absent from the model's tool
   list*, so it never attempts the call — verified in
   [../docs/verification/crew-spike.md](../docs/verification/crew-spike.md) (b).
   The base set plus the project's registered `allow=` commands, and nothing else.
3. **The injected `PreToolUse` guard.** Hooks fire regardless of permission mode,
   so `git push`, `gh pr merge`, `git worktree` and friends are refused even if
   the allowlist is wrong.

A crewmate never lands its own work. The supervisor does, under the delivery
mode recorded at spawn.

## Two sources of truth must agree

The brief records `mode=`; `spawn.sh` refuses a mismatch with its own `--mode`.
A crewmate obeys the brief and the supervisor ships by the flag, so those two
drifting apart is a delivery under a policy nobody chose.

## Where validation sits

The worktree **persists through validation**. Validators stay in-process
subagents of the orchestrator — read-only, adversarial, short — and run against
the worktree. They receive the diff and the handoff; the crewmate's context is
physically out of reach.

A red verdict does **not** tear down. The orchestrator appends a `## Followup`
to the same brief and steers the same crewmate on the same branch: a followup is
a re-brief, not a respawn. Teardown happens after green, or on abandon.

## Teardown is write-ahead

The completion links — PR URL, branch, worktree — live only in the record
teardown is about to delete. So the intent is written to
`state/<task>.close-pending` **first**. A process killed halfway leaves the next
session enough to finish; a failed delivery keeps its pending record, keeps the
worktree, and is retried rather than silently dropped.

## Steering is deterministic

`send.sh` writes the steer to `state/<task>.inbox/` **first**, then sends
`SIGUSR1`. `run.sh` interrupts its child, drains the inbox, and relaunches with
`--resume`, which keeps the same session and obeys the steer — verified in the
spike (a). No keystrokes into a TUI, no composer detection, no guessing whether
the pane was ready.

## Scouts

A scout is a brief with `## Report` in place of `## Definition of done`, a
read-only allowlist plus `Write` to the report path, and a teardown that keeps
the report and discards the branch. No commit, no PR.
