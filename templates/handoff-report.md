# Handoff Report Template

> Workers return content matching this exact shape. The Orchestrator persists it at `missions/<id>/features/NNN-<slug>/handoff.md`.

---

## Feature: F<NNN> — <slug>

### What was implemented

- bullet — short, concrete
- bullet
- bullet

### What was left undone

- bullet — reason
- (or write "Nothing")

### Commands run

| # | Command | Exit code | Notes |
|---|---------|-----------|-------|
| 1 | `pnpm typecheck` | 0 | clean |
| 2 | `pnpm test path/to/new.test.ts` | 0 | new tests added |
| 3 | `pnpm lint` | 0 | clean |

### Issues discovered

- bullet — anything the spec/contract didn't anticipate
- (or "None")

### Procedures followed

| Procedure | Followed | Notes |
|-----------|----------|-------|
| Wrote failing tests before implementation (TDD) | yes | added 4 cases before any prod code |
| Ran typecheck after each edit | yes | |
| Used existing utilities in `src/lib/` | yes | reused `parseAuthHeader` instead of writing new |
| Conventional commit message | yes | |

### Commits

- `<sha>` `feat(<slug>): <summary>`

---

## Alternative shapes

### SPEC-CLARIFICATION

If the spec was genuinely ambiguous and the Worker did not edit code:

```markdown
## Feature: F<NNN> — <slug> — SPEC-CLARIFICATION

### Ambiguity
- description of the unclear part

### Options I considered
- option A — implications
- option B — implications

### Recommendation
- which option, why
```

### BLOCKED

If the Worker hit a non-code blocker (missing creds, broken env):

```markdown
## Feature: F<NNN> — <slug> — BLOCKED

### Blocker
- description

### What I tried
- bullet

### What I need
- bullet (e.g. credentials in `.env.local`; a running database; a specific tool installed)
```
