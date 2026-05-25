# Validation Contract Template

> Saved at `missions/<id>/contract.md`. Written by the Orchestrator **before** any Worker spawns. The single source of truth for "done."

---

# Contract: <mission id>

## Preamble

- Repository: `<absolute path>`
- Branch base: `<branch>`
- Test runner: `<command>` (e.g., `pnpm test`, `pytest -q`, `cargo test`)
- Lint runner: `<command>`
- Typecheck runner: `<command>`
- Test command (Worker post-edit): `<command>` (e.g., `npm test`, `pytest -q`, `go test ./...`). Empty = no per-edit test. Only fast unit tests (<30s). Integration tests remain at contract-check time.
- Launch recipe (if user-facing): `<command>` + URL.

## Assertions

Each assertion has a stable ID. Features reference these IDs.

### C-001 — executable

**Statement.** The repository builds cleanly.

**Verification.**
```bash
<build command>
# expected: exit 0; stderr empty
```

### C-002 — executable

**Statement.** All existing tests pass after this mission.

**Verification.**
```bash
<test command>
# expected: exit 0; no skipped tests beyond those skipped in mission start state
```

### C-003 — executable

**Statement.** Typecheck is clean.

**Verification.**
```bash
<typecheck command>
# expected: exit 0
```

### C-004 — behavioral

**Statement.** No new dependencies were added without an entry in `docs/dependencies-rationale.md`.

**Verification.** Reader diffs `package.json` / `requirements.txt` / `Cargo.toml`. Any addition must have a corresponding new entry in the rationale file.

### C-005 — behavioral

**Statement.** No file in `src/` exceeds 800 lines after this mission.

**Verification.**
```bash
find src -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.py" -o -name "*.rs" \) -exec wc -l {} \; \
  | awk '$1 > 800 { print; bad=1 } END { exit bad }'
# expected: exit 0
```

### C-006 — behavioral / negative

**Statement.** No hardcoded secrets, tokens, or credentials in the diff.

**Verification.** Reader scans the full diff with a secret-scan tool (`gitleaks detect --staged --no-banner`). Any hit fails this assertion.

### C-007 — executable (user-facing missions)

**Statement.** The application boots and serves the index URL.

**Verification.**
```bash
<launch command> &
sleep 5
curl -fsS http://localhost:<port>/ > /dev/null
# expected: exit 0
```

### C-008+ — mission-specific

Add behavioral, executable, negative, accessibility, and performance assertions specific to this mission. Each must:
- Have a stable ID.
- Be independently verifiable.
- Be unambiguous to a reader who has never seen the code.

### Browser-specific assertion examples (for web UI missions)

### C-0XX — executable (browser)

**Statement.** Submitting the contact form with valid data shows a success confirmation.

**Verification.** (User-Testing Validator via Playwright MCP)
```
1. browser_navigate → http://localhost:<port>/contact
2. browser_fill → name field with "Test User"
3. browser_fill → email field with "test@example.com"
4. browser_fill → message field with "Hello"
5. browser_click → Submit button
6. browser_snapshot → verify element containing "Thank you" or "success" is visible
```

### C-0XX — executable (browser)

**Statement.** Clicking the "Dashboard" link navigates to /dashboard and shows the user's name.

**Verification.** (User-Testing Validator via Playwright MCP)
```
1. browser_navigate → http://localhost:<port>/
2. browser_click → "Dashboard" link
3. browser_snapshot → verify URL contains "/dashboard"
4. browser_snapshot → verify element containing user's name is visible
```

### C-0XX — executable (CI)

**Statement.** The CI pipeline passes on the current branch.

**Verification.** (Orchestrator or Scrutiny Validator via `gh` CLI)
```
1. Push the current branch: `git push -u origin <branch>`
2. Wait for CI: `gh run watch --exit-status`
3. Verify: exit 0 means all checks passed
```

> CI assertions are optional. Only add them when the target project has GitHub Actions configured.

### C-0XX — executable (integration)

**Statement.** The mission-required image generation integration is available and functional.

**Verification.** (Worker or Orchestrator)
```
1. Read integrations.json → confirm openai-image is enabled
2. Verify: test -n "$OPENAI_API_KEY"
3. Test call: curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $OPENAI_API_KEY" https://api.openai.com/v1/models
4. Expected: HTTP 200
```

> Integration assertions are optional. Only add them when the mission requires external services declared in `integrations.json`.

## Coverage check

Before approval, confirm:

- [ ] Every feature in `plan.md` cites at least one assertion.
- [ ] Every assertion has at least one feature owner.
- [ ] At least one **negative** assertion (no secrets, no swallowed errors, etc.).
- [ ] At least one **structural** assertion (file size, dep budget, etc.).
- [ ] At least one **behavioral** assertion per user-observable flow.
- [ ] Test runner and lint runner are named commands, not "all tests pass."

## Amendments log

Mid-mission edits to the contract land here, with timestamp and reason. **Never** weaken or remove an assertion to make a failing feature pass.

| Date | Assertion | Change | Reason | User approval |
|------|-----------|--------|--------|---------------|
| ... | ... | added/edited/removed | ... | yes/no |

## Approval

- [ ] Contract reviewed and approved by user
- Approved at: `<ISO timestamp>`
