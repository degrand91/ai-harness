---
name: feedback-settings-deny-rules
description: At intake, sanity-check `.claude/settings.json` deny rules for overbroad globs that would block mandatory mission artifacts.
metadata:
  type: feedback
---

When starting a new mission, glance at `.claude/settings.json` `permissions.deny` and confirm no rule blocks the standard mission artifacts (`mission.md`, `plan.md`, `contract.md`, `status.json`, `log.md`, `features/**`).

**Why:** On mission `2026-05-23-add-marker2`, an overbroad `Edit(./contract.md)` deny rule matched **every** `contract.md` under `missions/<id>/`, blocking the mandatory contract artifact mid-flow. The previous mission's contract had been written before the rule was added, so the breakage wasn't visible until a second mission was attempted. The user instructed me to fix the settings (option A) rather than work around it, validating the principle that harness defects get fixed, not worked around.

**How to apply:**
- At intake (step 2 of `/mission-start`, right after deciding the mission id and before scaffolding), do a quick `Read` of `.claude/settings.json` if I haven't this session.
- Specifically scan `permissions.deny` for any rule of the form `Edit(./<file>.md)` or `Write(./<file>.md)` without a leading directory anchor — those are project-wide matches, not top-level matches.
- If found, surface to the user immediately as a harness defect. Do not silently work around it; do not bypass with `--no-verify` analogues.
- Settings.json edits take effect mid-session (verified on this mission) — no restart needed after the user approves a fix.
