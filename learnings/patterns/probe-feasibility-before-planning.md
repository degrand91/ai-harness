---
name: probe-feasibility-before-planning
description: For "is this possible?" missions that hinge on an external format or API, spend the first 10–20 minutes running the real thing (parse a real file, hit the real endpoint) in a scratch dir before writing the plan — the probe output becomes the contract's literal expectations and turns the plan from speculation into facts.
introduced_in_mission: 2026-09-19-overlay-replay-import
tags: [planning, contract, research, feasibility]
---

## Pattern

The user asked "can we import build orders from a Warcraft 3 replay?". Instead of planning from library READMEs, the orchestrator downloaded a real patch-3.0 replay, ran `w3gjs` on it in Node, and printed the per-player order stream. That single probe (a) settled feasibility with evidence, (b) revealed a gap the README hides (hero training time is not in the high-level output), (c) produced the exact sequence for the contract (`Altar 0:03, Burrow 0:10, Barracks 0:35, Grunt 1:35`), and (d) later, a second probe of the W3Champions API (endpoint, CORS header, JSON shape) turned a user's off-hand link into a fully specified feature within minutes.

Rules of thumb: probe in the scratchpad, never in the target repo; paste the raw probe output into the spec's "verified facts" section; write contract assertions against the probe's numbers, not against prose; keep the probe artefact (the file, the JSON) as a fixture for the worker.

## Origin

`missions/2026-09-19-overlay-replay-import/post-mortem.md`. Related: [[verify-from-detached-scratch-worktree]], [[spec-fix-recipe-contradicts-contract-sequence]] (the same lesson applied to follow-ups).
