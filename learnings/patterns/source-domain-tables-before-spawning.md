---
name: source-domain-tables-before-spawning
description: When a feature depends on a numeric domain table (rule-set constants, tariffs, limits), the orchestrator fetches and cites the values at a polite rate BEFORE spawning the worker and puts them in the contract as a literal table; never write such numbers from memory and never delegate the lookup to a worker that may be bot-blocked.
introduced_in_mission: private
tags: [contract, data, research, planning]
---

## Pattern

Twice in two missions a worker faithfully implemented numbers the orchestrator had written from memory (first table: 20 values wrong; second table: 27 wrong). The second time the worker tried to verify them on a community wiki, was rate-limited, honoured the bot-block notice, and shipped `// unverified`. The fix that worked: the orchestrator fetched each value from another wiki's raw-page endpoint (`action=raw`, reading one template field) at one request every 2–3 s with a descriptive User-Agent, wrote the table with its source into the contract, and the follow-up worker only had to copy it. Cost: ~5 minutes. Benefit: the contract became literal and the scrutiny validator could diff the shipped table against it with a script.

Rules: domain numbers are **planning input** — source them during planning, cite the URL pattern, mark anything you could not verify, and make the contract assert the literal table. If a source blocks automated access, stop and use another (wiki mirrors, primary docs), do not retry or bypass.

## Origin

A mission on a private project; the post-mortem stays local. The predecessor incident (the first table) was an earlier mission on the same project. Related: [[probe-feasibility-before-planning]].
