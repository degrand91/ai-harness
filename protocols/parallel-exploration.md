# Protocol: Parallel Exploration

Explorer subagents are the **only** subagent type the Orchestrator may spawn concurrently during a mission. Every other subagent type is subject to the serial constraint defined in [protocols/serial-execution.md](serial-execution.md).

## The rule

Only `explorer` subagents may be spawned (or run) concurrently with other Agent calls. Workers, Scrutiny Validators, and User-Testing Validators must run one at a time, in order.

Explorers are read-only by design. They carry no `Write`, `Edit`, or `Bash` permissions. A batch of Explorers cannot corrupt the codebase, fork the architecture, or produce conflicting git state. That is why concurrent dispatch is safe for them and banned for everything else.

## When the Orchestrator may fan out

| Phase | Allowed? | Notes |
|-------|----------|-------|
| `intake` → `planning` (repo mapping) | ✅ | Primary use case. Map structure, locate hotspots, read dependencies. |
| `planning` (deep research on specific modules) | ✅ | Each Explorer answers one narrow question. |
| `contract` (verifying assumptions) | ✅ | Read-only fact-finding to sharpen assertion wording. |
| Between features (gap analysis) | ✅ | Useful if the next feature needs fresh context about what changed. |
| During feature implementation (Worker active) | ❌ | Unnecessary. The Worker already has focused scope. Avoid context noise. |
| During validation (Scrutiny or User-Testing active) | ❌ | Validators must see a stable codebase. Do not fan out while they run. |

**The canonical window is the transition from `intake` to `planning`:** fan out Explorers to map the repo, then synthesise before writing `plan.md`.

## Recommended concurrency

The recommended maximum concurrency is 3–5 explorers per fanout. Beyond 5, synthesis overhead outweighs the speedup and the Orchestrator's context window fills with low-signal results. If a question genuinely requires more than 5 sub-queries, break it into two sequential fanout rounds.

## Each Explorer asks ONE narrow question

Split the exploration space into non-overlapping questions before dispatching. Examples of well-formed questions:

- "List every file under `protocols/` with its first heading."
- "Find all places `subagent_type` is referenced in `.claude/` and summarise the usage pattern."
- "What does `missions/<id>/status.json` look like? Extract its schema."

Avoid broad questions like "explain the whole codebase." Broad prompts produce overlapping, redundant answers that are hard to synthesise and waste context.

## Background mode

Dispatch Explorers with `run_in_background: true`. This keeps their intermediate output out of the Orchestrator's active context until synthesis time. The Orchestrator then reads each Explorer's result once, extracts the signal, and discards the raw output.

If background mode is unavailable in the current client, dispatch the Explorers and do not read their results until all have finished.

## Synthesis

After all Explorers in a fanout batch have finished:

1. Read each result in order.
2. Merge non-contradictory findings into a single context block (for the Orchestrator's internal use or for the `/explore` skill to return).
3. Flag any contradictions for manual inspection before plan writing.
4. Discard raw Explorer output — it should not persist into `plan.md` verbatim. Distil into decisions.

The `/explore` skill (when available) handles steps 1–4 automatically. If you are running without the skill, follow the steps above manually.

## Anti-patterns

- ❌ Spawning a Worker and Explorers at the same time. Explorers are planning tools, not implementation sidecars.
- ❌ Giving an Explorer a write-adjacent task ("summarise, then update the README"). Explorers must stay read-only.
- ❌ Fanning out more than 5 Explorers without a synthesis plan.
- ❌ Letting Explorer results sit unread in the background indefinitely. Collect and distil before advancing the lifecycle.
- ❌ Using Explorers as a substitute for writing a clear plan. Exploration feeds planning; it does not replace it.

## Cross-references

- [protocols/serial-execution.md](serial-execution.md) — the master rule on what may and may not run in parallel.
- [protocols/lifecycle.md](lifecycle.md) — the state machine showing where exploration fits in the mission flow.
