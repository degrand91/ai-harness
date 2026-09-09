# GitHub Integration Protocol

> **Status: PARTLY IMPLEMENTED.**
>
> Implemented: PR creation and CI polling at teardown (`scripts/crew/teardown.sh`,
> `scripts/pr-poll.sh`), and the crewmate guard that refuses `gh pr merge`.
> Not implemented: issue-driven mission intake, and the review-comment loop.

This protocol covers three GitHub-specific integration points in the harness:
issue-driven intake, CI assertion support, and automatic issue closing at
mission close. All three rely on the `gh` CLI.

---

## Prerequisites

- The `gh` CLI must be installed and authenticated (`gh auth status` exits 0).
- The target repository must have a GitHub remote (`git remote -v` shows a
  `github.com` URL).
- Issue closing requires write access to the source repository's issue tracker.
- CI assertions require the repository to have at least one GitHub Actions
  workflow configured under `.github/workflows/`.

---

## Issue-Driven Intake

When a user passes a GitHub issue URL as the mission goal, the Orchestrator
fetches the issue before scaffolding the mission folder.

### Steps

1. Detect a GitHub issue URL in `$ARGUMENTS`. The canonical form is:
   `https://github.com/<owner>/<repo>/issues/<number>`.

2. Fetch issue metadata:
   ```bash
   gh issue view <url> --json title,body,labels
   ```

3. Populate `mission.md`:
   - Use the issue `title` as the mission slug basis.
   - Use the issue `body` verbatim as the goal text.
   - Add a `## Source` section at the bottom of `mission.md` containing the
     original issue URL. Example:
     ```
     ## Source
     https://github.com/owner/repo/issues/42
     ```
   - Labels from the issue may inform the mission's tag metadata.

4. If `gh auth status` fails, fall back to treating the URL as plain-text goal
   and log a warning in `log.md`: `[WARN] gh not authenticated — issue fetch
   skipped`.

### Example

```
/mission-start https://github.com/acme/api/issues/42
```

The Orchestrator fetches issue #42, derives the mission id from the title
(e.g., `2026-05-24-fix-rate-limit-headers`), records the body as the verbatim
goal, and stores the issue URL in `mission.md` under `## Source`.

---

## Issue Closing at Mission Close

At the end of `/mission-review`, if `mission.md` contains a `## Source`
heading with a GitHub issue URL, the Orchestrator closes the issue with a
summary comment.

### Steps

1. Read `missions/<id>/mission.md`. Grep for `## Source` and extract the URL.

2. If a URL is found, close the issue:
   ```bash
   gh issue close <url> \
     --comment "Resolved via harness mission <id>. See post-mortem for details."
   ```

3. If `gh auth status` fails, or the repo does not have write permissions, log
   the failure in `log.md` and continue — issue closing is non-blocking.

4. If no `## Source` heading exists, skip this step silently.

---

## CI Assertion Type

The `executable (CI)` assertion type delegates verification to the GitHub
Actions CI pipeline rather than running checks locally.

### When to Use

Add a CI assertion when:
- The target project has GitHub Actions workflows.
- The contract needs to verify that the full CI matrix (multi-OS, multi-version)
  passes, not just a single local run.
- The feature adds or changes a workflow file itself.

### Template

```markdown
### C-0XX — executable (CI)

**Statement.** The CI pipeline passes on the current branch.

**Verification.** (Orchestrator or Scrutiny Validator via `gh` CLI)
1. Push the current branch: `git push -u origin <branch>`
2. Wait for CI: `gh run watch --exit-status`
3. Verify: exit 0 means all checks passed
```

### Behaviour

- `gh run watch --exit-status` blocks until the most recent run completes and
  exits non-zero if any job fails.
- The Orchestrator or Scrutiny Validator runs this in a `Bash` tool call.
- CI assertions count as executable assertions for coverage purposes.

### Limitations

- Requires a push to a remote branch; not suitable for fully local-only repos.
- Long-running CI pipelines may exhaust the tool call timeout — set a
  `timeout_minutes` guard in the workflow if needed.
- Private repos require a `gh` token with `repo` scope.

---

## Example End-to-End Workflow

1. A GitHub issue is opened: "Add rate-limit headers to the API."
2. User runs: `/mission-start https://github.com/acme/api/issues/42`
3. Orchestrator fetches the issue, scaffolds the mission, and records the URL
   in `mission.md` under `## Source`.
4. Mission executes through the normal feature loop.
5. Contract includes a CI assertion: `gh run watch --exit-status` on the
   feature branch.
6. All assertions pass. Orchestrator runs `/mission-review`.
7. `mission-review` detects the source issue URL and closes issue #42 with a
   summary comment linking to the post-mortem.
