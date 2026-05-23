---
name: tighten-validator-role-prompt
description: Add an explicit "your reply must begin with `## Feature:` or `## Verdict:`" gate to scrutiny-validator and user-testing-validator role prompts.
introduced_in_mission: 2026-05-23-add-marker2
status: accepted
tags: [validator, agent-prompts, parsing]
---

## Proposal

Edit `.claude/agents/scrutiny-validator.md` and `.claude/agents/user-testing-validator.md` to replace the current "return only the verdict markdown" language with a hard-bounded rule:

> Your reply MUST begin with the literal characters `## Feature:` or `## Verdict:` (matching the template heading exactly). Any text before that heading, or any text after the final template section, is a protocol violation. The Orchestrator will discard it and may re-spawn you.

Two reasons to do this:

1. The current phrasing ("return only the verdict markdown") is a soft instruction. Chat-trained models override it with a polite preamble (`"I'll create the verdict directly..."`). Yesterday's mission flagged it; today's confirmed recurrence with the identical pattern, identical model (Haiku Scrutiny). Two for two.
2. A literal-character gate is parseable on the orchestrator side without ambiguity. The next iteration can add a PostToolUse hook that strips anything before `## Feature:` automatically and re-spawns if the marker is absent.

## Why now

- Confirmed recurrence across two missions. Not a one-off.
- The fix is a one-line edit in two files.
- It unblocks a downstream improvement (automatic verdict extraction).

## Risks

- The Haiku validator might fail to comply even with a stronger gate. If so, escalate to "re-spawn on protocol violation" automatically rather than letting prose drift through.
- Other agents may use similar phrasing; check `.claude/agents/worker.md` too for the parallel "your reply must begin with `## Feature:`" rule and harmonize wording.

## Origin

`missions/2026-05-23-add-marker2/post-mortem.md` — recurrence of [[validator-prose-preamble]]. Proposed but not implemented yesterday; bumping with empirical reinforcement.

## Implementation

Implemented in mission `2026-05-23-ship-v0-3-multi-provider` feature **F005 — defensive-verdict-parsing**. The original proposal's first prong (tightening validator role prompts) is moot — the prompts were already strict (scrutiny-validator.md already had a "Format rule (zero tolerance)" section). The second prong (orchestrator-side defensive parsing) is what shipped: the orchestrator now strips any text preceding the first `## Feature:` or `## Verdict:` heading before persisting validator verdicts to disk.
