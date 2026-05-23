---
name: validator-prose-preamble
description: Validator subagents tend to wrap the structured verdict in a conversational preamble, breaking downstream parsing.
introduced_in_mission: 2026-05-22-add-marker
tags: [validator, scrutiny-validator, prompt, parsing]
---

## Anti-pattern

A Validator subagent (Scrutiny or User-Testing) returns the required verdict markdown **plus** a short prose paragraph before or after it ("Perfect, all assertions pass. ..."). This violates the role prompt's "return only the verdict markdown" rule. It also breaks any downstream tool that expects the output to start with `## Feature:`.

Observed once on Haiku in the smoke-test mission. Expect the same on Sonnet; chat-style models default to a pre/post note.

## Why it's tempting

The model is trained to be helpful and conversational. Returning bare structured output feels abrupt. The role prompt is asking the model to override a deeply trained default.

## What to do instead

1. **Strengthen the role prompt.** In `agents/scrutiny-validator.md` and `agents/user-testing-validator.md`, replace "Return only the verdict markdown" with a more specific gate: *"Your reply must begin with the literal characters `## Feature:` and end with the closing line of the last specified section. Any text before `## Feature:` or after the last section is a protocol violation and the verdict will be rejected."*
2. **Defensive parsing.** The Orchestrator should persist only the block starting at the first `## Feature:` heading and ending at the next `---` (or EOF). Strip everything outside that range.
3. **(Optional, v0.3 hook)** A PostToolUse hook on Agent calls that detects prose-before-verdict and re-spawns the Validator once.

## Origin

`missions/2026-05-22-add-marker/post-mortem.md` — smoke-test mission. Scrutiny Validator on Haiku emitted a single-paragraph preamble; verdict content itself was correct.

## Recurrence log

- **2026-05-23 (mission `2026-05-23-add-marker2`)** — Same model (Haiku Scrutiny). Preamble: `"I'll create the verdict directly based on the contract requirements and format expectations."` Verdict body was correct; defensive orchestrator parsing absorbed the drift. Proves the role-prompt fix has not been applied yet. See `learnings/proposals/tighten-validator-role-prompt.md`.
- **2026-05-23 (mission `2026-05-23-ship-v0-3-multi-provider`)** — Recurred on 5 of 7 Scrutiny passes (F001, F002, F004, F006-minimal; F003 + F005 + F007-self compliant). 8 confirmed instances across 3 missions, ~9 Haiku scrutiny passes. F005's orchestrator-side defensive verdict-parsing rule was shipped this mission and resolves the operational impact. The underlying anti-pattern (model fails to comply with strict format rule) is **stubborn but absorbed**. Candidate follow-up: switch default Scrutiny model to Sonnet on missions with subjective assertions.
