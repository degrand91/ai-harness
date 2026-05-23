# Learnings Index

> Auto-regen this file via `scripts/learnings-index.sh` once it ships in v0.4. Until then, append manually at mission close.

## Patterns

- [sanity-check-settings-deny-at-intake](patterns/sanity-check-settings-deny-at-intake.md) — At intake, scan `.claude/settings.json` deny rules for overbroad globs that would block mandatory mission artifacts. (from `2026-05-23-add-marker2`)

## Anti-patterns

- [validator-prose-preamble](anti-patterns/validator-prose-preamble.md) — Validators wrap verdicts in conversational prose; tighten role prompt + defensively parse. (from `2026-05-22-add-marker`; recurred in `2026-05-23-add-marker2`)

## Proposals

- [tighten-validator-role-prompt](proposals/tighten-validator-role-prompt.md) — Make the "reply must begin with `## Feature:` / `## Verdict:`" rule a literal-character gate in validator prompts. (accepted in 2026-05-23-ship-v0-3-multi-provider; from `2026-05-23-add-marker2`)
