---
name: project-chain-state
description: Current state of the v0.3 → v1.0 chain mission. Read at session start if the user references the harness roadmap.
metadata:
  type: project
---

**As of 2026-05-23T10:56:00Z** — chain target v1.0, blanket approval given (`"you dont need my approval continue until v1"`).

**Why:** user kicked off a multi-mission marathon to ship the harness roadmap. Each phase ships as its own mission. Orchestrator runs the loop autonomously, surfacing only at chain end or on genuine blockers.

**How to apply (at next session start):**

1. Read `ROADMAP.md` — see which `## vX.Y` headings are ticked ✅.
2. Read `missions/` for closed missions (each has a `post-mortem.md` and `status.json` with `state: "closed"`).
3. The next mission to start is the one targeting the next un-ticked roadmap phase. As of this memory's write:
   - ✅ v0.1–v0.9 (last: `2026-05-23-ship-v0-9-background-missions`).
   - 🔜 **v1.0 — Production** (FINAL — chain endpoint).
4. Honor [[feedback-blanket-approval]] — skip the approval gate; drive directly into intake → plan → contract → execute → close → next mission.
5. Read [[validator-prose-preamble]], [[recursive-mission-stability-guards]], [[contract-defect-amend-not-patch]] before authoring the next contract. These are now part of the orchestrator's standard authoring kit.
6. Wall-clock-bound exit criteria (v0.7 paused-and-resumed; v0.9 overnight; v1.0 ≥7-day mission) cannot be satisfied in a single session — ship the infrastructure, document the gap in CHANGELOG known-gaps section.

**Why this is a memory, not just a log:** the chain crosses session boundaries. The orchestrator that picks this up in a fresh session needs to know it's mid-chain, not starting fresh.

**Chain-end terminus:** v1.0 ticked ✅ in `ROADMAP.md`. At that point, surface a chain-end summary to the user.
