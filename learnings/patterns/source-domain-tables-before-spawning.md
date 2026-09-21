---
name: source-domain-tables-before-spawning
description: When a feature depends on a numeric domain table (game constants, tariffs, limits), the orchestrator fetches and cites the values at a polite rate BEFORE spawning the worker and puts them in the contract as a literal table; never write such numbers from memory and never delegate the lookup to a worker that may be bot-blocked.
introduced_in_mission: 2026-09-19-replay-import-accuracy
tags: [contract, data, research, planning]
---

## Pattern

Twice in two missions a worker faithfully implemented numbers the orchestrator had written from memory (food costs: 20 wrong; train times: 27 wrong). The second time the worker tried to verify them on Liquipedia, was rate-limited, honoured the bot-block notice, and shipped `// unverified`. The fix that worked: the orchestrator fetched each value from warcraft.wiki.gg (`action=raw`, `|buildtime=`) at one request every 2–3 s with a descriptive User-Agent, wrote the table with its source into the contract, and the follow-up worker only had to copy it. Cost: ~5 minutes. Benefit: the contract became literal and the scrutiny validator could diff the shipped table against it with a script.

Rules: domain numbers are **planning input** — source them during planning, cite the URL pattern, mark anything you could not verify, and make the contract assert the literal table. If a source blocks automated access, stop and use another (wiki mirrors, primary docs), do not retry or bypass.

## Origin

`missions/2026-09-19-replay-import-accuracy/post-mortem.md`; predecessor incident in `missions/2026-09-19-overlay-replay-import` (food table). Related: [[probe-feasibility-before-planning]].
