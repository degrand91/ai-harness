# Protocol: Serial Execution

Features run **one at a time**. This is non-negotiable. Correctness compounds over multi-day runs; parallelism compounds errors.

## The rule

At any moment, **at most one Worker subagent is active**. The next Worker reads the codebase via git, not via shared memory.

## Why

- Two Workers editing concurrently fork the architecture. Their commits collide; their assumptions drift.
- Sequential Workers see a coherent codebase produced by the prior Worker. The history is linear and reviewable.
- Validation can run between features and catch regressions early.
- Slower clock time. Faster correct time.

## What is allowed in parallel

Only **read-only, non-conflicting** work:

| Task | Parallel? | Why |
|------|-----------|-----|
| Codebase exploration via Explorer subagents | ✅ | Read-only. No state collision. |
| API/library research via WebFetch/WebSearch | ✅ | External. No state collision. |
| Doc reads | ✅ | Read-only. |
| Scrutiny Validator on past feature N while Worker runs feature N+1 | ❌ | Don't. Validate before advancing — protects from compounding errors. |
| Scrutiny Validator on feature N while User-Testing Validator on the same feature N | ✅ | Same artifact, independent checks. Both finish before the next Worker spawns. |
| Multiple Workers on different features | ❌ | Banned. |

## Practical patterns

### Fan out exploration before planning
Spawn 3–5 Explorer subagents in parallel during the `planning` state to map the repo. Each answers one narrow question. The Orchestrator synthesises.

### Stagger validators for one feature
After a Worker hands off feature N:
1. Scrutiny + User-Testing Validators can run **in parallel** against the same feature.
2. Both must finish before feature N+1 starts.

### Don't pre-spawn the next Worker
Tempting to spawn feature N+1 while validators are still running on N. Don't — if N fails, N+1's premises change.

## How to enforce

- The Orchestrator does not call the Agent tool twice in the same message for two Worker spawns.
- A future hook (`hooks/pre-subagent-block-parallel-workers.sh`) will reject double-spawns once `hooks/` is wired in v0.3.

## Anti-patterns

- ❌ "Let's parallelise these two features for speed."
- ❌ "I'll start feature N+1 while N validates, just to save time."
- ❌ Spawning Worker subagents from different terminals against the same mission folder.
- ❌ Letting Explorers edit code "because it would have been faster."
