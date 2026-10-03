---
name: act-on-stale-pr-state
description: The orchestrator updates, pushes to, specs against or reports on a PR from memory of its state, while the user has already merged it from another session; the follow-up lands on a dead branch. Before any PR action, read `gh pr view <n> --json state,mergedAt` and `origin/main`.
introduced_in_mission: private
tags: [orchestrator, git, github, pr, multi-session, sync]
---

## Anti-pattern

The orchestrator remembers "PR #N is open, waiting for the user" and acts on it
hours later: a worker spec targets the PR branch, a validator reviews it, the
orchestrator runs `gh pr update-branch`, reports "conflicts", pushes a merge
commit. Meanwhile the user merged it minutes after it opened.

Observed four times in one mission: a follow-up spec targeted an already merged
PR, a follow-up feature landed after its PR was merged, `gh pr update-branch`
plus a pushed merge commit hit a PR merged two days earlier, and a cost analysis
claimed a merged PR was still open.

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
- Open a PR only when everything on it is proven: some users merge a PR as soon
  as it appears, so a PR's existence must mean "ready to merge". Accumulate
  follow-ups on the branch, not in new PRs.

## Origin

A mission on a private project; the post-mortem stays local.
