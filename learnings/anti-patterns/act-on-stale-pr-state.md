---
name: act-on-stale-pr-state
description: The orchestrator updates, pushes to, specs against or reports on a PR from memory of its state, while the user has already merged it from another session; the follow-up lands on a dead branch. Before any PR action, read `gh pr view <n> --json state,mergedAt` and `origin/main`.
introduced_in_mission: 2026-09-30-extract-overlay-dedicated-repo
tags: [orchestrator, git, github, pr, multi-session, sync]
---

## Anti-pattern

The orchestrator remembers "PR #N is open, waiting for the user" and acts on it
hours later: a worker spec targets the PR branch, a validator reviews it, the
orchestrator runs `gh pr update-branch`, reports "conflicts", pushes a merge
commit. Meanwhile the user merged it minutes after it opened.

Observed in this mission four times: the F004b spec targeted the merged overlay
PR #2, F005b landed after #5 was merged, `gh pr update-branch 52` plus a pushed
merge (916e1bb) on site PR #52 two days after its merge, and an earlier claim
that site PR #35 was unmerged and "still live" during a cost analysis.

## Why it's tempting

The orchestrator opened the PR and asked for the merge, so its own transcript
says "waiting". The user merges from GitHub or another session without saying
so, and the local checkout does not change.

## What to do instead

- Before any action on a PR (spec, push, update, comment, "ready to merge"),
  run `gh pr view <n> --json state,mergedAt` and `git fetch -p` then read
  `origin/main`.
- Treat a surprising failure ("conflicts", "nothing to merge") as the signal
  that state moved, not as a problem to fix.
- Open a PR only when everything on it is proven: this user merges a PR as soon
  as it appears, so a PR's existence must mean "ready to merge". Accumulate
  follow-ups on the branch, not in new PRs.

## Origin

[post-mortem](../../missions/2026-09-30-extract-overlay-dedicated-repo/post-mortem.md).
