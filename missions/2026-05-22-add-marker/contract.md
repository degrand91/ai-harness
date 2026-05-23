# Contract: 2026-05-22-add-marker

## Preamble

- Repository: `/tmp/harness-test`
- Branch base: existing default branch (single commit history)
- Test runner: n/a (empty repo)
- Lint runner: n/a (empty repo)
- Typecheck runner: n/a (empty repo)
- Launch recipe: n/a (no app)

## Assertions

### C-001 — executable — Owner: F001

**Statement.** `MARKER.md` exists at the repo root after the feature.

**Verification.**
```bash
test -f /tmp/harness-test/MARKER.md
# expected: exit 0
```

### C-002 — executable — Owner: F001

**Statement.** `MARKER.md` contains today's ISO date (`2026-05-22`) on a line by itself, and nothing else.

**Verification.**
```bash
[ "$(cat /tmp/harness-test/MARKER.md)" = "2026-05-22" ]
# expected: exit 0
```

### C-003 — executable — Owner: F001

**Statement.** The most recent commit message starts with `feat(add-marker):`.

**Verification.**
```bash
cd /tmp/harness-test && git log -1 --pretty=%s | grep -qE '^feat\(add-marker\): '
# expected: exit 0
```

### C-004 — executable — Owner: F001

**Statement.** The most recent commit changes exactly one file: `MARKER.md`.

**Verification.**
```bash
cd /tmp/harness-test && [ "$(git diff-tree --no-commit-id --name-only -r HEAD)" = "MARKER.md" ]
# expected: exit 0
```

### C-005 — behavioral / negative — Owner: F001

**Statement.** No secrets, tokens, or credentials anywhere in the diff (sanity check; not expected on this mission).

**Verification.** Reader scans the diff for patterns matching `(SECRET|TOKEN|API_KEY|PASSWORD|sk_[a-zA-Z0-9]{16,})`. Any hit fails this assertion.

## Coverage check

- [x] Every feature in `plan.md` cites at least one assertion (F001 cites C-001..C-004).
- [x] Every assertion has at least one feature owner.
- [x] At least one negative assertion (C-005).
- [x] At least one structural assertion (C-004 — single-file diff).
- [x] At least one behavioral assertion verifying observable state (C-002).
- [x] Test/lint/typecheck commands explicitly marked n/a where the repo doesn't have them — no false "all tests pass" assertion.

## Amendments log

_(none)_

## Approval

- [x] Contract reviewed and approved by user (smoke-test pre-approval given in chat)
- Approved at: `2026-05-22T23:49:14Z`
