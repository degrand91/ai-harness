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
