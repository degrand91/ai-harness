---
name: pr-evidence
description: Capture and post visual evidence (before/after screenshots, viewport variants, an accessibility note) of a feature's user-observable change to its pull request, so a human reviewer sees what changed without checking out the branch. Use after a user-observable feature lands as a PR. Reuses the evidence the user-testing-validator already captured; captures fresh via Playwright MCP only if none exists. Harness-native — no third-party upload service.
disable-model-invocation: true
argument-hint: <feature-id> [pr-url-or-number]
allowed-tools: Read, Bash, Grep, Glob
---

## Feature / PR
$ARGUMENTS

## Current date
!`date -u +%Y-%m-%dT%H:%M:%SZ`

---

You are the Orchestrator closing the evidence loop on a pull request. The goal:
a reviewer opening the PR **sees the change working** — before/after, the key
states, desktop + mobile — without pulling the branch. This is the thing a human
PR review most wants and most rarely gets from an autonomous run.

Run this for a **user-observable (T2)** feature after its PR exists. For a
back-end-only change there is nothing to show — skip it.

## 0. Preconditions

- `gh auth status` exits 0 (the target repo has a GitHub remote). If not, log a
  warning and stop — this step is non-blocking, never fail the mission for it.
- You know the feature id and its PR. Resolve the PR from the branch if not given:
  ```bash
  gh pr view --json number,url,headRefName    # run in the target repo checkout
  ```

## 1. Gather the evidence (reuse first, capture only if missing)

The `user-testing-validator` already stores screenshots under
`missions/<id>/features/<n>/evidence/` with a zero-padded, chronological naming
convention (see [browser-qa](../browser-qa/SKILL.md) §5). **Use those** — do not
re-shoot what already exists.

```bash
ls missions/<id>/features/<n>/evidence/*.png 2>/dev/null
```

Only if the folder is empty (e.g. the feature shipped at T1 but is in fact
user-observable): capture a minimal set now with the Playwright MCP tools from
[browser-qa](../browser-qa/SKILL.md) — the launch recipe is in the feature's
`spec.md` / handoff. Capture, at minimum:

- the **before** state (baseline, or the prior behavior if reconstructable),
- the **after** state proving the change,
- the **key intermediate** state if the flow has one (filled form, open modal),
- a **mobile** (≈390 px) and **desktop** (≈1440 px) variant of the main state,
- one `browser_snapshot` to back a one-line accessibility note (labels present,
  focus sane).

Store anything you capture in the same evidence folder with the same naming.

## 2. Make the images reachable by the PR

GitHub renders an image in a comment only from a URL. Default method, no external
service:

1. Commit the evidence PNGs onto the **PR branch** under a clearly-scoped path so
   they are easy to spot and drop:
   ```bash
   mkdir -p .pr-evidence/<feature-id>
   cp missions/<id>/features/<n>/evidence/*.png .pr-evidence/<feature-id>/
   git add .pr-evidence/<feature-id>
   git commit -m "chore(evidence): <feature-id> visual evidence for review [skip ci]"
   git push
   ```
2. Reference each image by its raw URL:
   `https://raw.githubusercontent.com/<owner>/<repo>/<branch>/.pr-evidence/<feature-id>/<name>.png`

**Branch hygiene.** This adds a commit to the PR. Say so in the comment, and note
it is safe to drop: a squash-merge removes it automatically; for a merge-commit
flow, the reviewer can ignore or `git rm` it before merge. If the project's
delivery mode or the captain forbids any non-product commit on the branch, use
the fallback below instead.

**Fallback (no branch pollution):** post the comment with the evidence described
in a table and attached as a **gist**:
```bash
gh gist create missions/<id>/features/<n>/evidence/*.png --public=false --desc "<feature-id> evidence"
```
link the gist, and embed its raw blob URLs. Gists render PNGs by raw URL the same
way. Choose this when the branch must stay product-only.

## 3. Post the evidence comment

Build a markdown comment and post it:

```bash
gh pr comment <pr-number-or-url> --body-file <path-to-generated-md>
```

The comment body must contain, in this order:

1. A one-line heading: `### 🖼️ Visual evidence — <feature-id> <slug>`.
2. A **before → after** pair embedded inline (`![before](url)` `![after](url)`).
3. A short **table**: each captured state → thumbnail/link, with its viewport.
4. One **accessibility line** from the `browser_snapshot` (e.g. "All interactive
   elements have accessible names; focus returns to trigger on modal close").
5. A **provenance footer**: which validator/verdict produced it, the commit sha
   under test, and "captured by `/pr-evidence`, harness mission `<id>`".

Keep it scannable — a reviewer should grasp the change in ten seconds.

## 4. Record it

Append one line to the mission `log.md`:
`[<ts>] pr-evidence posted for <feature-id> → <pr-url> (<n> images, method=branch|gist)`.
Update the feature's `status.json` with an `evidence_posted_at` timestamp. This is
the signal the feature-loop delivery step keys off (see
[protocols/feature-loop.md](../../../protocols/feature-loop.md)).

## What NOT to do

- ❌ Post evidence for a back-end-only change — there is nothing to see.
- ❌ Fail the mission because `gh` is unauthenticated or the repo is local-only —
  this step is non-blocking. Log and move on.
- ❌ Fabricate screenshots or describe states you did not actually capture. If the
  app could not be launched, say so in the comment rather than inventing evidence.
- ❌ Upload to any third-party service other than the repo's own GitHub (gist
  included) — no external evidence stores.
