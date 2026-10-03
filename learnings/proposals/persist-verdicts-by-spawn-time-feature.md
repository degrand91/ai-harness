---
name: persist-verdicts-by-spawn-time-feature
description: The SubagentStop hook files a report under status.json.current_feature at STOP time; when the orchestrator advances current_feature while an earlier feature's validator is still running, the verdict lands in the wrong feature folder. Record the target feature at spawn time instead.
introduced_in_mission: private
tags: [harness, hooks, subagent-stop, verdicts, bookkeeping]
---

## Problem

Two user-testing reports for feature F009 were written to the folder of its
follow-up, F009a, because F009a had become `current_feature` while those F009
validators ran. The orchestrator noticed and moved them by hand; a less careful
run would have read an F009 verdict as F009a's.

Concurrent work across features is legitimate here: a re-test of the previous
feature while the follow-up worker runs in a separate worktree.

## Proposal

- The PreToolUse (Agent) hook already sees every spawn. Have it record
  `{agent_id or description, feature}` from the spawn prompt's `## Feature:` or
  description (e.g. "User test – F009 ...") into the spawn-state file.
- SubagentStop resolves the folder from that record, and falls back to
  `current_feature` only when no record exists.
- As a cheap interim check: if the report's own `## Feature: F<id>` heading
  disagrees with `current_feature`, file it under the heading's feature and log
  a warning.

## Origin

A mission on a private project; the post-mortem stays local.
