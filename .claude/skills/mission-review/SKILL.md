---
name: mission-review
description: Close a mission. Runs the full validation contract as integration check, writes the post-mortem, and distills at least one entry into learnings/. Use at the end of every mission, including abandoned ones. Disable-model-invocation — the Orchestrator decides explicitly to review.
disable-model-invocation: true
argument-hint: [mission-id]
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

## Available missions
!`ls -1 ${CLAUDE_PROJECT_DIR}/missions 2>/dev/null | grep -v '^\\.gitkeep$' || echo "(none)"`

## Argument
Mission id (or empty = most recent): $ARGUMENTS

---

Close out a mission. Run the post-mortem ritual and distill at least one reusable learning.

## Procedure

1. **Determine mission id** (argument, or most-recent if empty).

2. **Pre-check.** Verify `status.json.state == "closing"` or `"closed"` and the last full contract run was green. If a feature is still red, refuse to review — say "mission has red features F<N>; cannot review until closed". If the user wants to **abandon**, accept that and write a post-mortem with `state at close: abandoned`.

3. **Re-run the full contract as integration check.** Use `/contract-check <mission-id>` or run the assertions in `contract.md` directly. Record the result.

4. **Author `post-mortem.md`** using `templates/post-mortem.md`. Required sections:
   - Summary (one paragraph: what shipped).
   - Features executed (table: ID, slug, first-pass result, follow-ups).
   - Validator failures by assertion (which tripped, why).
   - Cost & tokens (aggregate per-role from each feature's `status.json`).
   - What worked / What was hard / What to keep / What to change.
   - Anti-patterns observed.
   - Distilled learnings (links to new `learnings/` entries).

5. **Identify** (be specific — name the assertion, the model, the file):
   - The slowest feature. Why?
   - The feature with the most follow-ups. Why? (Often a contract defect.)
   - The validator failure mode that recurred (if any).

6. **Distill at least one of**:
   - **Pattern**: a reusable approach that worked → `learnings/patterns/<slug>.md`.
   - **Anti-pattern**: a recurring failure mode → `learnings/anti-patterns/<slug>.md`.
   - **Proposal**: a protocol/template/prompt edit → `learnings/proposals/<slug>.md`.

   Use the templates in `learnings/README.md`. Include frontmatter (`name`, `description`, `introduced_in_mission`, `tags`). Include an `Origin` link back to this mission's post-mortem for traceability.

7. **Update `learnings/INDEX.md`** with one-line entries pointing at the new file(s).

8. **Update `status.json`**: set `state: "closed"` (or `"abandoned"`), `closed_at: <now UTC>`, `post_mortem_path: "post-mortem.md"`. Append to `log.md`.

9. **Surface the post-mortem path and new learnings** to the user.

## Anti-patterns

- ❌ Review with no learnings entry. Every mission produces at least one.
- ❌ Generic learnings ("be more careful next time"). Specifics only.
- ❌ Skipping cost aggregation.
- ❌ Editing the contract retroactively to make the integration check pass.
