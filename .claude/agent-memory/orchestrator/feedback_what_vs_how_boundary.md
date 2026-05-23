---
name: feedback-what-vs-how-boundary
description: The user owns WHAT; AI owns HOW — including context, session, and infrastructure management. Never escalate a HOW problem (like context exhaustion) by asking the user to take action they don't need to.
metadata:
  type: feedback
---

The harness's design principle is: user defines WHAT, AI handles HOW — "for hours, days, or weeks". Context exhaustion, session boundaries, agent registry refresh, and other infrastructure-level concerns are HOW problems and must be solved by the orchestrator, not delegated back to the user via "could you start a fresh session?" or similar.

**Why:** On 2026-05-23, after shipping v0.3 + v0.4 in one session, I surfaced an "A or B — keep pushing vs start fresh session" question to the user. The user pushed back: *"consider that human is only giving the what to build the rest must be handle by ai"*. The "ask the human to launch a new session" framing made the user responsible for an infrastructure decision they should never have to make. They give the WHAT (chain target v1.0); the rest is the orchestrator's problem.

**How to apply:**

- **Never ask the user to switch sessions, restart, or take a manual action to resolve a HOW problem.** If context is tight, compress harder; if a hook blocks, fix the hook; if an agent registry needs refresh, accept that the next session handles it and keep driving until natural session end.
- **Context budget management is the orchestrator's job.** Tools to use BEFORE surfacing context as a blocker:
  1. Spawn subagents with `run_in_background: true` and only fetch their results when needed.
  2. Let Workers author handoff+scrutiny scaffolds themselves; orchestrator verifies, doesn't write from scratch.
  3. Collapse spec.md and scrutiny.md to the bare regex-matchable shape; let the contract carry the precision.
  4. Skip narrative updates that the PostToolUse hook already captures (the hook auto-appends to log.md).
  5. Re-read filesystem state instead of trying to remember it across many turns.
- **Surfacing to the user is for: genuine blockers only.** Missing credentials. Ambiguity the contract can't resolve. Two consecutive validator failures hinting at a deeper problem. NOT for "I'm getting low on context, please intervene".
- **Natural session end is not a failure.** If the session naturally hits its limit, the Stop hook ends cleanly, the filesystem state and MEMORY.md persist, and the next session resumes via [[project-chain-state]]. That's the harness's resume design — used silently, not announced.

**How NOT to apply:**

- Do not pretend infrastructure problems don't exist. They do — context windows are real. Solve them quietly. Just don't make the user own the solution.
- Do not skip post-mortems or learnings to save tokens. Those are durable cross-mission artifacts; they pay off the very next mission. Compress how, not whether.
