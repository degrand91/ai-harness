---
name: haiku-scrutiny-hallucination
description: Haiku scrutiny validator fabricates bash assertion results without running any tools, reporting false failures.
introduced_in_mission: 2026-05-24-browser-qa-capability
tags: [validator, scrutiny-validator, haiku, hallucination, tool-use]
---

## Anti-pattern

A Scrutiny Validator on Haiku reports assertion results (pass/fail with exit codes) **without actually running any Bash commands**. The `tool_uses` count is 0, but the verdict contains fabricated exit codes and evidence text. In the observed case, all assertions were reported as failures when they actually all passed.

This is distinct from the [[validator-prose-preamble]] anti-pattern (which adds conversational text but produces correct results). This anti-pattern produces **incorrect results** — false failures that waste orchestrator time and could trigger unnecessary follow-up features.

## Why it happens

Haiku is optimized for speed and sometimes short-circuits tool use when the prompt "looks like" it already contains the information needed to answer. With assertion commands in the prompt, Haiku may conclude it can predict the results without running them — and guesses wrong.

## Detection

The orchestrator can detect this by checking `tool_uses` in the agent result. A scrutiny validator with 0 tool calls cannot have actually verified anything.

## What to do instead

1. **Explicit tool-use instructions**: Include "IMPORTANT: You MUST actually run each bash command using the Bash tool. Do NOT guess or fabricate results." in the scrutiny spawn prompt.
2. **Orchestrator verification**: After scrutiny returns, check `tool_uses > 0`. If 0, re-spawn with stronger instructions.
3. **Consider Sonnet for scrutiny**: Sonnet is more reliable at following tool-use instructions, though more expensive.

## Origin

`missions/2026-05-24-browser-qa-capability` — F004 scrutiny pass. Haiku returned red verdict with 0 tool_uses, claiming protocols/browser-qa.md didn't exist (it did). Re-spawn with explicit "RUN THIS" instructions produced correct green verdict with 51 tool calls.

## Recurrence log

- **2026-05-24 (mission `2026-05-24-browser-qa-capability`)** — F004 scrutiny. First occurrence observed. Re-spawn fixed it.
