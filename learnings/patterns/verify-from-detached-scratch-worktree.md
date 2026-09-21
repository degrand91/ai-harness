---
name: verify-from-detached-scratch-worktree
description: When a human shares the mission worktree and may leave uncommitted (even non-compiling) edits there, workers and validators must never stash/checkout/reset/restore/clean it — they stage only their own paths and run typecheck/lint/test/build from a detached scratch worktree at the commit under test, then remove it.
introduced_in_mission: 2026-09-18-overlay-private-builds
tags: [worker, validator, git, shared-worktree, verification]
---

## Pattern

The user works in a second Claude session on the same branch/worktree and leaves WIP in it — in this mission a half-finished prefill feature with a syntax error. A user-testing validator, trying to get a clean build, ran `git stash` on that WIP (recovered by the orchestrator). From then on every prompt carried two rules that made the rest of the mission safe and reproducible:

1. **Never** `git stash`, `checkout`, `restore`, `reset`, or `clean` in the target worktree. Commit only with explicit paths (`git add <own files>`), never `-A`/`-a`.
2. **Verify elsewhere:** `git worktree add <scratchpad>/<name> <sha> --detach && pnpm install --frozen-lockfile` there; run the runners, preview and browser scripts from it; `git worktree remove --force` it at the end. Red→green proofs (reverting a file to `git show HEAD~1:path`) also happen in the scratch copy.

The orchestrator applies the same rule to the integration check: run the contract against the branch tip in a scratch worktree, not against a dirty shared tree. Side benefit: the check is honest about what is *committed*, not what happens to be on disk.

## Origin

`missions/2026-09-18-overlay-private-builds/post-mortem.md`. Related: [[host-adapter-for-native-app-validation]] (why browser validation works from a plain `dist/`), memory `feedback_shared_branch_parallel_user_commits`.
