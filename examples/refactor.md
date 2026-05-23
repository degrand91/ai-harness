# Example: Large-Scale Refactor — Cookie Auth → JWT Across 30 Endpoints

A worked example of a refactor mission. Key themes: feature ordering for stability, regression
guards written before the first line of code changes, and an A/B testing pattern that lets
old and new auth coexist until the cutover is confirmed green.

This is **descriptive**, not prescriptive. The real protocol lives in [CLAUDE.md](../CLAUDE.md).

---

## Scenario

**User:** "Our Express API still uses `express-session` + server-side cookies for auth. We need
to switch every protected endpoint to accept a Bearer JWT instead. There are 30 endpoints across
8 routers. Existing session-based tests must stay green throughout. Zero downtime cutover."

---

## Intake snapshot

**`missions/2026-05-23-cookie-to-jwt/mission.md` (excerpt)**

```markdown
# Mission: cookie-to-jwt
id: 2026-05-23-cookie-to-jwt
state: executing
goal: >
  Migrate all 30 protected Express endpoints from express-session cookie auth
  to Bearer JWT auth. Existing session tests must stay green until formal cutover.
  Zero downtime: old and new auth run in parallel until cutover feature is merged.
approved_at: 2026-05-23T11:05Z
```

---

## Explorer fanout (5 in parallel, read-only)

Explorers answer: *what exactly are we touching?*

- **E1**: "List every route file under `src/routes/`. For each, count how many handlers call
  `req.session` or `requireAuth`. Return file:line references."
- **E2**: "What does the current `requireAuth` middleware do? Show full implementation."
- **E3**: "What test runner + coverage tool? What is the current coverage baseline? Any existing
  JWT library in `package.json`?"
- **E4**: "Are there any integration tests that start an actual server and set cookies? List them."
- **E5**: "Is there a `.env.example`? Does it already contain a `JWT_SECRET` field?"

Explorer E1 returns the definitive list of 30 endpoints grouped by router. This list becomes the
tracking table in `plan.md`.

---

## Plan snapshot

**`missions/2026-05-23-cookie-to-jwt/plan.md` (excerpt)**

```markdown
## Feature order

F001  regression-baseline      — Snapshot current passing tests; add a CI step that fails if
                                 any previously-passing test is newly skipped or red.
F002  jwt-infrastructure        — Add `jsonwebtoken`, write `src/middleware/authenticateJWT.ts`,
                                 issue + verify tokens. Unit tests only. Session middleware untouched.
F003  dual-auth-middleware       — Wrap both authenticators: request accepted if EITHER valid session
                                 cookie OR valid Bearer token present. Replaces `requireAuth` calls
                                 in all 30 endpoints. No endpoint removed from session auth yet.
F004  migrate-routes-batch-1    — Convert routers: users, profiles (10 endpoints). Remove session
                                 dependency from these routers only. Dual-auth still active elsewhere.
F005  migrate-routes-batch-2    — Convert routers: posts, comments, tags (12 endpoints).
F006  migrate-routes-batch-3    — Convert routers: admin, billing, notifications (8 endpoints).
F007  cutover                   — Remove dual-auth wrapper; `requireAuth` now resolves to
                                 `authenticateJWT` only. Remove `express-session` dependency.
F008  cleanup                   — Delete session-related test helpers, remove `SESSION_SECRET`
                                 from `.env.example`, remove `connect-pg-simple` dependency.

## Why this order?
F001 before any code changes ensures the baseline is captured, not inferred.
F002 before F003 means JWT logic is reviewed in isolation before it touches production paths.
Batching (F004–F006) limits blast radius per feature; each batch is independently reviewable.
F007 is a one-line swap once all routes are confirmed green in dual-auth mode.
```

---

## Contract snapshot

**`missions/2026-05-23-cookie-to-jwt/contract.md` (excerpt)**

```markdown
## Assertions

C-001  exit 0   pnpm test (baseline captured in F001; any regression blocks merge)
C-002  exit 0   pnpm typecheck
C-003  exit 0   pnpm lint
C-004  behavioral  No call to req.session exists in any file under src/routes/ after F007 merges
C-005  exit 0   grep -r "req\.session" src/routes/ (must exit 1, i.e., zero matches = grep returns 1)
         Note: wrapped as: ! grep -r "req\.session" src/routes/
C-006  behavioral  JWT_SECRET is read from process.env; no literal string passed to jwt.sign/verify
C-007  exit 0   grep -rn "jwt\.sign\|jwt\.verify" src/ | grep -v "process\.env\.JWT_SECRET" (must be empty)
         Wrapped: [ -z "$(grep -rn "jwt\.sign\|jwt\.verify" src/ | grep -v process.env.JWT_SECRET)" ]
C-008  exit 0   After F003, curl with valid cookie returns 200 on GET /api/users/me
C-009  exit 0   After F003, curl with valid Bearer token returns 200 on GET /api/users/me
C-010  exit 0   After F007, curl with valid cookie returns 401 on GET /api/users/me
C-011  behavioral  express-session not present in package.json after F008
C-012  exit 0   pnpm test --coverage (coverage must not drop below pre-mission baseline)
```

---

## A/B testing pattern (dual-auth middleware)

F003 introduces a middleware that accepts *either* credential type:

```typescript
// src/middleware/requireAuth.ts  (F003 state — dual-auth)
export const requireAuth = (req, res, next) => {
  const fromJWT   = verifyBearer(req);
  const fromCookie = req.session?.userId;
  if (fromJWT || fromCookie) {
    req.userId = fromJWT ?? fromCookie;
    return next();
  }
  return res.status(401).json({ error: 'Unauthorized' });
};
```

This means **no existing session-based test breaks during F004–F006** — the old path still
works while new JWT paths are being plumbed. C-008 and C-009 both pass simultaneously.

C-010 is only asserted *after* F007 merges, confirming the old path is gone.

---

## Stability guard detail

**F001 produces a baseline artifact**, not just a passing CI run. The Worker writes
`tests/baseline-snapshot.json` containing:
- List of test names that passed
- Coverage percentage (lines, branches)

The contract (C-012) asserts that coverage after F008 meets or exceeds the baseline value. The
Scrutiny Validator for every subsequent feature checks this file was not modified.

---

## Feature loop highlights

### F003 — dual-auth-middleware

Scrutiny Validator specifically checks:
1. `req.session` is still reachable via the old path (C-008 precondition).
2. `jwt.verify` is called with `process.env.JWT_SECRET`, not a literal (C-006).
3. No mutation: `req.userId` is assigned once; no object is modified in place.

User-Testing Validator fires here because F003 is user-observable:
- It logs in with a cookie, hits `/api/users/me`, asserts 200.
- It generates a token via the new `POST /auth/token` endpoint, hits `/api/users/me` with Bearer,
  asserts 200.

### F007 — cutover

This feature changes exactly one file: `src/middleware/requireAuth.ts`. It is intentionally
narrow. Scrutiny checks that no other file was modified beyond removing session imports.

---

## Lessons reinforced by this shape

- **Baseline capture (F001) before any edit.** Without it, the contract cannot assert "coverage
  did not drop" — you can only assert it is above some arbitrary floor.
- **Dual-auth buys you safety without complexity.** Two paths, one middleware, tested independently.
  Cutover (F007) then becomes a trivially reviewable diff.
- **Grep-as-assertion is underused.** C-005 and C-007 are exit-code-based grep checks — no test
  framework needed. Scrutiny can verify them in seconds.
- **Batch routing by router, not by file size.** Batching by logical grouping (users + profiles,
  posts + comments, admin + billing) means each batch can be end-to-end tested at the router level
  with an isolated test file, and a bug in billing auth doesn't require retouching users.
