---
name: probe-feasibility-before-planning
description: For "is this possible?" missions that hinge on an external format or API, spend the first 10–20 minutes running the real thing (parse a real file, hit the real endpoint) in a scratch dir before writing the plan — the probe output becomes the contract's literal expectations and turns the plan from speculation into facts.
introduced_in_mission: private
tags: [planning, contract, research, feasibility]
---

## Pattern

The user asked whether data could be imported from a third-party binary file format. Instead of planning from library READMEs, the orchestrator downloaded a real sample file, ran an open-source parser on it in Node, and printed the event stream. That single probe (a) settled feasibility with evidence, (b) revealed a gap the README hides (one timing field is not in the high-level output), (c) produced the exact timestamped sequence for the contract, and (d) later, a second probe of a third-party public API (endpoint, CORS header, JSON shape) turned a user's off-hand link into a fully specified feature within minutes.

Rules of thumb: probe in the scratchpad, never in the target repo; paste the raw probe output into the spec's "verified facts" section; write contract assertions against the probe's numbers, not against prose; keep the probe artefact (the file, the JSON) as a fixture for the worker.

## Origin

A mission on a private project; the post-mortem stays local. Related: [[verify-from-detached-scratch-worktree]], [[spec-fix-recipe-contradicts-contract-sequence]] (the same lesson applied to follow-ups).
