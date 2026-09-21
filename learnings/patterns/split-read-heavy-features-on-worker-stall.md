---
name: split-read-heavy-features-on-worker-stall
description: When a worker stalls (stream watchdog, no output) during the read/exploration phase of a broad "port this UI" feature, do not retry the same spec a third time — split it into a foundation feature and a component-by-component port, each with an explicit read budget ("≤ N reads, first write within 5 tool calls") and per-component sed ranges.
introduced_in_mission: 2026-09-18-overlay-no-focus-steal
tags: [worker, spec, reliability, ui]
---

## Pattern

Three consecutive workers stalled on the same feature ("restyle the picker to match the website"), each after ~15–40 tool calls of reading site source, with the tree still clean. The stalls were stream hangs after tool results, not task failures — but a broad "read all these reference files, then port" spec maximises the exposure. What worked: split into **F003a** (fonts, CSS tokens, assets — a list of literal edits) and **F003b** (an ordered port list `site file → overlay file` with the classes spelled out), and prepend a work-style rule: read with `sed -n` ranges ≤ 90 lines, at most N reads before the first write, first write within 5 tool calls. Both halves completed first try (47 and 151 tool calls).

Corollary for orchestrators: put the reference *content* the worker needs (class lists, line ranges, exact rule names) into the spec so the worker's read phase is short and deterministic; a spec that says "port faithfully from these six files" is an invitation to read everything.

## Origin

`missions/2026-09-18-overlay-no-focus-steal/post-mortem.md` (F003 → F003a/F003b). Related: [[spec-prescribe-framework-idioms]].
