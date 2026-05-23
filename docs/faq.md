# Harness FAQ

## What is the harness?

The harness is a thin protocol layer on top of Claude Code that implements the Factory-Missions pattern: one long-lived Orchestrator, many short-lived Workers, and adversarial Validators, all glued together by a validation contract written before any code exists. It has no runtime of its own — it is markdown protocols, templates, shell hooks, and Claude Code subagent definitions.

## When should I use the harness?

Use it when:

- The goal has multiple distinct features or steps that must be delivered sequentially.
- You want adversarial verification: the entity that builds something should not be the same entity that checks it.
- The mission spans more than one session (resumability matters).
- You want a permanent paper trail: every state transition is a file in `missions/`.
- You are building something where a mistake in feature N cascades into features N+1 through N+k, and catching it early matters.

## When should I NOT use the harness?

Skip the harness when:

- The task is a single self-contained edit, a bug fix, or a one-shot question. Overhead exceeds benefit.
- You need a result in the next five minutes. The approval gate and contract-writing add deliberate friction.
- The output is exploratory or throwaway — a prototype you will delete. The harness is optimised for missions you care about shipping correctly.
- You have no meaningful acceptance criteria. The validation contract requires executable assertions. If you cannot write them, the harness cannot help you.

## How is this different from just prompting Claude?

Three things distinguish the harness from a long chat session:

1. **Separation of implementation and verification.** Workers never see Validator reasoning. Validators never see Worker reasoning. This kills sunk-cost bias — the Validator is adversarially fresh on every feature.
2. **Contract-first.** The validation contract is written before any code. Tests written after implementation confirm bias; the contract avoids it.
3. **Persistence.** Every state transition is a file. A fresh session tomorrow can read `status.json` and resume exactly where the last session stopped.

## What does a mission cost in tokens?

Rough order-of-magnitude per feature:

- **Worker (Sonnet):** 20 000–80 000 input tokens depending on codebase size and feature complexity.
- **Scrutiny Validator (Haiku):** 5 000–15 000 tokens (reads the diff and runs assertions).
- **User-Testing Validator (Sonnet):** 10 000–30 000 tokens (tool use heavy).
- **Orchestrator overhead (Opus):** 5 000–10 000 tokens per feature (planning, handoff recording, status updates).

A 5-feature mission typically costs the equivalent of 3–6 hours of pair-programming with Sonnet. If cost is the primary constraint, use Haiku workers for trivial features and set `model: haiku` in the spawn call.

## Can a mission start another mission (recursive missions)?

Yes, with guards. The Orchestrator can spawn a Worker whose feature spec is "scaffold and execute a sub-mission." The guard is: the sub-mission must not mutate the parent mission's `status.json` or `log.md`. Each mission has its own `missions/<id>/` folder; they do not share state. See `learnings/patterns/recursive-mission-stability-guards.md` for stability patterns and failure modes.

## What is the approval gate and can I skip it?

The approval gate is the one mandatory human checkpoint in the lifecycle: after the plan and contract are written, the Orchestrator presents both to the user and waits for explicit approval before spawning any Worker. The standard flow does not skip it. Operators running chained missions may grant **blanket pre-approval** by stating it explicitly at chain-start (e.g., "continue until v1.0"); see `.claude/agent-memory/orchestrator/feedback_blanket_approval.md`. Even with blanket approval, the orchestrator still authors plan + contract artifacts and surfaces only on genuine blockers. The gate exists because fixing a wrong contract after 8 features have been built costs an order of magnitude more than fixing it at the gate.

## Can Workers run in parallel?

No. Workers always run one at a time. Each Worker inherits the codebase via git — the next Worker depends on the previous Worker's commit being in the tree. Explorer subagents (read-only recon) may run in parallel; the `pre-agent-spawn-serial.sh` hook enforces this rule and will block concurrent non-explorer spawns.

## What happens when a Validator returns red?

The Orchestrator opens a **follow-up feature** in the same mission. It does not patch the original feature in place. The follow-up feature is given the failing assertions from the Validator's verdict as its acceptance criteria. This keeps the audit trail clean — the original feature's `handoff.md` records what was attempted, and the follow-up records what fixed it.

## Do I need to stay at my computer during a mission?

No. From v0.9 the harness supports headless mode: `claude --agent orchestrator -p "..."` runs unattended. The Notification hook fires at the approval gate (and optionally at close), delivering a macOS Notification Center alert or a Slack message. You return at the gate, approve, and let it run again.

## How do I inspect what is happening without spending tokens?

Run `scripts/status.sh` from the harness root. It reads `missions/<id>/status.json` and `log.md` without invoking Claude. For richer views, `scripts/mission-tui.sh` and `scripts/mission-html-report.sh` produce terminal and browser outputs respectively.
