# Validation Verdict Template

> Validators (Scrutiny and User-Testing) return content matching this shape. Persisted at `missions/<id>/features/NNN-<slug>/scrutiny.md` or `.../user-test.md`.

---

## Feature: F<NNN> — <slug> — <Scrutiny|User-Testing> Verdict: <green|red>

### Assertions evaluated

| ID | Statement | Result | Evidence |
|----|-----------|--------|----------|
| C-001 | builds cleanly | pass | `pnpm build` exit 0 |
| C-003 | typecheck clean | pass | `pnpm typecheck` exit 0 |
| C-005 | no file in src/ > 800 lines | pass | `find ... | awk` exit 0 |
| C-006 | no hardcoded secrets | fail | `gitleaks` found `STRIPE_KEY=sk_test_...` at `src/lib/billing.ts:42` |

### Adversarial findings (Scrutiny only)

- bullet
- (or "None")

### User flows exercised (User-Testing only)

| # | Flow | Result | Evidence |
|---|------|--------|----------|
| 1 | sign in with valid creds | pass | `features/NNN/evidence/01-signin.png` |
| 2 | sign in with bad creds | fail | server returned 500; expected 401 — `features/NNN/evidence/02-bad-creds.png` |

### Boot (User-Testing only)

- launched: yes
- launch command: `pnpm dev`
- url: `http://localhost:3000`
- evidence: `features/NNN/evidence/boot.png`

### Console errors / network failures observed (User-Testing only)

- bullet
- (or "None")

---

## Follow-up specs (only if verdict is red)

Write one minimal feature description per failed assertion. The Orchestrator will sequence them.

### Follow-up 1

- **Title:** Remove hardcoded Stripe key, load from env
- **Failing assertion(s):** C-006
- **Scope:** `src/lib/billing.ts`
- **Acceptance:** `gitleaks detect` exits 0 on the new diff.

### Follow-up 2

- **Title:** Return 401 on bad credentials
- **Failing assertion(s):** (the contract assertion ID covering this flow)
- **Scope:** auth handler
- **Acceptance:** User-Testing flow #2 passes.
