---
name: show-the-output-before-the-pipeline
description: Building watchers, pipelines, UI and a release for a feature whose actual output the user has never seen; on 2026-10-02 a six-feature mission was scrapped at the first look ("does not give much to the user"). Compute one real example of the output at planning time and show it at the approval gate.
introduced_in_mission: 2026-10-02-overlay-replay-review
tags: [planning, approval-gate, product, prototype]
---

## Anti-pattern

The plan delivers a pipeline (detect → parse → compare → store → render → release), and the contract checks that each stage is correct. Nobody checks whether the end result is worth having until the user tries the finished build.

2026-10-02: a post-game "plan vs actual" review for a WC3 overlay. Seven features, 8.5 hours. On the user's first look: "i feel the check of last match and compare to the build order does not give much to the user let's scrap this idea". At planning time, every input already existed: the replay API, a captured real response, the 41 live builds. A 30-line script could have produced a real review ("0/33 on plan · 9 early · 11 late · 13 missed") in minutes.

## Why it's tempting

The approval gate shows a plan and a contract, which are about correctness, so value questions do not come up. The user approves an idea that sounds good in a bullet list.

## What to do instead

- For any feature whose value is its **output** (a report, a score, a recommendation, a summary), compute one or two real examples during planning, from real data, with a throwaway script, and put them in front of the user **at the approval gate**: "this is what you would see after your last game. Worth building?"
- Order the plan so the smallest end-to-end slice that shows real output comes first (e.g. "Review a replay file…" over the existing import), and put watchers, pipelines and release work after the user has seen it.
- When the example looks harsh or noisy (here: 0 on plan for a normal game), raise that at the gate: it is a product question, not a tuning task.

## Origin

[post-mortem](../../missions/2026-10-02-overlay-replay-review/post-mortem.md).
