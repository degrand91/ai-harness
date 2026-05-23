---
name: feedback-blanket-approval
description: On this project, the user grants blanket approval to skip the per-mission approval gate when they say "continue", "you don't need my approval", or similar — and expects chained-mission execution without re-asking.
metadata:
  type: feedback
---

When the user gives an explicit blanket directive of the form *"you don't need my approval"*, *"continue until vX"*, *"do not stop until ready"*, treat it as pre-approval for **every mission in the chain it implies**. Drive the feature loop autonomously across mission boundaries.

**Why:** On 2026-05-23, after running two smoke-test missions through the standard approval gate, the user said "create a team of agents and plan and execute the roadmap so that we go to release test it and do not stop until is ready" → and when I surfaced a v0.3 plan for approval anyway, replied "you dont need my approval continue until v1". They expected the orchestrator to honor the pre-approval and chain missions through v1.0 without further gates. This OVERRIDES the harness's "approval gate is mandatory" hard rule **for the chain explicitly scoped by the user**. The rule reverts to default for goals outside that scope.

**How to apply:**

- When a user message contains explicit blanket pre-approval language for a multi-mission chain, set a mental flag for the duration of that chain and stop pausing at the approval gate.
- Still author `mission.md`, `plan.md`, `contract.md` for each mission — these artifacts have value beyond approval (Workers and Validators read them).
- Still tick the approval boxes (use the user's blanket-approval message as the timestamp source).
- Still escalate on **genuine blockers**: missing credentials, ambiguous direction the contract cannot resolve, two consecutive validator failures on the same feature suggesting a contract defect, wall-clock-bound exit criteria the orchestrator cannot satisfy in-session.
- Distinguish "blanket approval for this chain" from "skip the gate forever" — if the user opens a new unrelated goal later, the gate is back on by default unless they re-grant blanket approval.
- After mission close, do not pause to ask "should I continue?" — proceed to the next mission in the chain immediately. Surface progress in the log; surface the chain-end summary only when v1.0 (or the explicit terminus) is reached.

**How NOT to apply:**

- Do not extend this to bypass the Stop hook's "no red status" guard. That guard exists to catch unfinished work, not to gate user approval.
- Do not extend this to skip writing the contract. The contract is the Validator's only source of truth — it is not an approval artifact, it is an execution artifact.
- Do not skip post-mortems. Each mission still distills at least one learning.
