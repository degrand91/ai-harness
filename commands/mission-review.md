# Command: mission-review

> Invoke at mission close, or post-hoc to audit a completed mission.

## What it does

Runs the post-mortem ritual and distills at least one reusable learning.

## Procedure

1. Verify `status.json.state == "closed"` and last full contract run was green. If not, refuse to review until the mission is actually closed.
2. Read all artifacts under `missions/<id>/`.
3. Author `post-mortem.md` using [templates/post-mortem.md](../templates/post-mortem.md).
4. Aggregate per-role token/cost from each feature's `status.json` into the post-mortem cost table.
5. Identify:
   - The slowest feature. Why?
   - The feature with the most follow-ups. Why? (Often a contract defect.)
   - The validator failure mode that recurred. Why?
6. Distill at least one of:
   - **Pattern**: a reusable approach that worked — write to `learnings/patterns/<slug>.md`.
   - **Anti-pattern**: a recurring failure mode — write to `learnings/anti-patterns/<slug>.md`.
   - **Proposal**: a protocol/template/prompt edit — write to `learnings/proposals/<slug>.md`.
7. Update `learnings/INDEX.md`.
8. Surface the post-mortem path and the new learnings entries to the user.

## Output

- `missions/<id>/post-mortem.md` populated and signed off.
- At least one new entry under `learnings/`.

## Anti-patterns

- ❌ Review with no learnings entry. Every mission produces at least one.
- ❌ Generic learnings ("be more careful next time"). Specifics only — name the assertion, the model, the file.
- ❌ Skipping the cost aggregation.
