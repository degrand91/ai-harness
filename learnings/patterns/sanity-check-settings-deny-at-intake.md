---
name: sanity-check-settings-deny-at-intake
description: At mission intake, scan .claude/settings.json `permissions.deny` for overbroad globs that would block mandatory mission artifacts.
introduced_in_mission: 2026-05-23-add-marker2
tags: [intake, settings, permissions, harness-config]
---

## Pattern

At the start of every mission, before scaffolding the mission folder, the Orchestrator reads `.claude/settings.json` and inspects `permissions.deny` for any entry that could block the standard mission artifacts (`mission.md`, `plan.md`, `contract.md`, `status.json`, `log.md`, `features/**`).

Specifically, watch for `Edit(...)` or `Write(...)` rules whose path lacks a leading directory anchor:
- ❌ `Edit(./contract.md)` — matches `contract.md` anywhere under the project, including every mission's contract.
- ✅ `Edit(./contract.md)` only if a top-level `./contract.md` is the actual intended target and no other file by that name exists in subdirectories — verify by `find . -name contract.md`.

When a candidate overbroad rule is found, **surface it to the user and offer to remove or narrow it**. Do not work around it silently.

## Why

Overbroad deny rules block the harness lifecycle invisibly. On mission `2026-05-23-add-marker2`, an `Edit(./contract.md)` rule was added to protect the mission's contract from late-stage edits. The intent was reasonable; the glob was wrong. It matched `missions/<id>/contract.md` for every mission and blocked the mandatory contract authorship step. The prior mission's contract had been written before the rule existed, so the defect didn't surface until a second mission was attempted on a new day — fully ten hours into the harness's lifetime. The class of bug is "harness blocks itself on its second use" and is exactly the kind of failure the validation-contract gate exists to catch — but only if the orchestrator runs the check.

## How to apply

1. **Within `/mission-start`, step 2 (Decide mission id)**, do a `Read` of `.claude/settings.json` if it hasn't been read this session.
2. Scan `permissions.deny` for any `Edit(...)` or `Write(...)` rule whose path is a filename glob without a directory prefix tying it to a top-level location.
3. For each suspect rule: run `find . -name <filename>` to count matches. If more than one match exists, the rule is over-broad against the harness's per-mission artifact structure.
4. Surface findings before scaffolding:
   > "Settings rule `Edit(./X)` would block N files in this repo, including expected mission artifacts. Recommend removing or scoping it. Continue with the rule as-is, fix it now, or abandon?"
5. If the user fixes it, re-read `settings.json` to confirm; Claude Code applies permission changes mid-session — no restart needed.

This pattern is cheap (one Read + one find) and catches a class of harness-config defects that block silently.

## Origin

`missions/2026-05-23-add-marker2/post-mortem.md` — second smoke-test mission. The `Edit(./contract.md)` deny rule had been in place since v0.2 (commit `e14bb2f`) and blocked the contract.md write on this mission's first attempt. User chose to fix the settings (option A) rather than work around it. Fix was a single-line removal from `permissions.deny`.
