---
name: show-the-output-before-the-pipeline
description: Building watchers, pipelines, UI and a release for a feature whose actual output the user has never seen; a seven-feature mission was scrapped at the first look ("does not give much to the user"). Compute one real example of the output at planning time and show it at the approval gate.
introduced_in_mission: private
tags: [planning, approval-gate, product, prototype]
---

## Anti-pattern

The plan delivers a pipeline (detect → parse → compare → store → render → release), and the contract checks that each stage is correct. Nobody checks whether the end result is worth having until the user tries the finished build.

Observed: an automatic "plan vs actual" report for a desktop app. Seven features, 8.5 hours. On the user's first look, the feature was scrapped as not useful. At planning time every input already existed (the source API, a captured real response, the reference data). A 30-line script could have produced a real report in minutes.

## Why it's tempting

The approval gate shows a plan and a contract, which are about correctness, so value questions do not come up. The user approves an idea that sounds good in a bullet list.

## What to do instead

- For any feature whose value is its **output** (a report, a score, a recommendation, a summary), compute one or two real examples during planning, from real data, with a throwaway script, and put them in front of the user **at the approval gate**: "this is what you would see. Worth building?"
- Order the plan so the smallest end-to-end slice that shows real output comes first, and put watchers, pipelines and release work after the user has seen it.
- When the example looks harsh or noisy (for example, a score of zero for a normal input), raise that at the gate: it is a product question, not a tuning task.

## Origin

A mission on a private project; the post-mortem stays local.
