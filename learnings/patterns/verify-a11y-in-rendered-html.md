# Pattern: Verify accessibility/structure against rendered HTML, not source greps

**Context:** Web missions where a contract asserts something about semantic structure (an `<h1>`, an `aria-labelledby` target, one landmark per region).

## Problem

Source-level greps are easy to satisfy and easy to fool:

- `grep -Eq 'aria-labelledby|<h1' page.tsx` passes if **either** token appears — so a page with `aria-labelledby` but no `<h1>` (heading rendered as `<h2>` by a shared component) slips through.
- Even `grep '<h1'` on source can't tell you **where the `id` actually lands**: in a mission on a private web project, a shared heading component put the section's `id` on its wrapper `<div>`, not the `<h1>`. So the section's `aria-labelledby` resolved to the div, not the heading. Source greps said "pass"; the prerendered HTML revealed the truth.

## Pattern

For structural/a11y assertions, **build the app and grep the prerendered output**, not the JSX:

```bash
bun run build           # or the framework's static export
grep -c '<h1' .next/server/app/<route>.html          # exactly one
grep -o '<h1[^>]*id="X"' .next/server/app/<route>.html # id on the heading
grep -o '<div id="X"'   .next/server/app/<route>.html  # must be ABSENT
```

And pair it with a **live user-testing pass** for the behavioral half (heading visible, link navigates).

Two corollaries:
- Avoid `OR` greps (`aria-labelledby|<h1`) for "must have an h1" — they let one branch mask a missing requirement. Assert each property independently.
- When a shared component (e.g. a heading wrapper) mediates the markup, check that the prop you pass lands on the element you think it does — verify in built HTML, and keep changes additive so other call sites stay byte-identical.

## Payoff

Catches the subtle "looks right in source, wrong in the DOM" class of a11y bugs that grep-only contracts miss. Sonnet-tier scrutiny is worth it for this judgment; mechanical Haiku scrutiny will pass the grep and move on.

Related: [[contract-baseline-correction]]
