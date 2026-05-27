# Pattern: Research-Only Missions

**Source:** `2026-05-26-littlestorywand-ux-audit`
**Confidence:** high (worked cleanly first time)

## Context

When the user's goal is research, analysis, or report generation rather than code changes, the harness still works — but requires adjustments.

## Pattern

1. **Workers produce markdown artifacts, not code commits.** Since `missions/` is gitignored, there are no committable diffs. Brief workers explicitly: "no commit expected, write your findings to `<path>`."

2. **Contract assertions for research quality use three layers:**
   - **Structural:** file exists, line count in range, no target repo modifications
   - **Behavioral:** keyword coverage (e.g., "does the report mention X, Y, Z as distinct sections?"), heading count, severity-tagged findings count
   - **Negative:** no placeholders (TBD/TODO), no fabricated data markers, no secrets

3. **Scope negative assertions to the deliverable, not the mission directory.** A recursive grep on `missions/<id>/` will match the contract.md itself if the search pattern appears in the assertion definition. Scope to `report.md` or `findings.md` instead.

4. **Explorer fanout is extra valuable for research missions** because the orchestrator needs deep domain understanding to write the plan and contract — there's no "just build it" shortcut.

5. **Market research workers need WebSearch access** and should use live APIs (e.g., iTunes Search) rather than relying on training data for competitor info. Brief them to cite data sources.

## Anti-pattern

Don't skip the contract because "it's just a report." Research deliverables need quality gates too — without assertions, workers produce generic, un-grounded analysis.
