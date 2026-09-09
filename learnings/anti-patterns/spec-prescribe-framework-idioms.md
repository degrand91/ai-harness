# Anti-pattern: Telling a worker to change links without prescribing the framework's idiom

**Seen in:** `2026-06-10-add-about-us-section`, F002 → F003.

## What happened

The orchestrator's F002 spec told the worker to change the nav's bare hash anchors (`#approach`) to root-relative form (`/#approach`, `/#top`) so they'd work from a non-home route. The worker did exactly that — using plain `<a href="/#top">`. In Next.js, a literal `<a>` pointing at an internal route trips the lint rule `@next/next/no-html-link-for-pages`. Result: a lint regression (C-003 red) and a whole extra follow-up feature (F003) to swap in `next/link`.

## Why it's a trap

When you instruct a routing/link change in a framework that has an opinionated navigation primitive (Next `<Link>`, React Router `<Link>`, etc.), saying *what* to link without saying *how to link it* invites the worker to use the raw HTML element — which the framework's linter rejects. The orchestrator effectively authored the regression.

## Do instead

- When the spec changes internal navigation, **name the framework primitive**: "use `next/link`'s `<Link>` for any root-relative/internal link; bare `<a>` is only for hash-only or external URLs."
- Better: before specifying it, check the project's lint config / existing components for the established pattern and cite it in the spec.
- General rule: if your instruction touches an area the project's linter has opinions about (links, images, `<head>` tags), pre-empt the lint rule in the spec rather than discovering it via a red verdict.

## Cost of the trap

One extra worker spawn + scrutiny round (~30k tokens) for what should have been a one-line correctness detail in the original spec.

Related: [[contract-baseline-correction]]
