---
name: stale-dev-cache-false-red
description: A user-testing validator reads computed styles from a long-running Next.js (Turbopack) dev server after the checkout changed branch; the served CSS still lacks the new Tailwind classes, so it reports a confident red (e.g. "stripe is transparent") for code that is correct. A plain restart is not enough: the compiled CSS persists in `.next/dev`.
introduced_in_mission: 2026-09-30-extract-overlay-dedicated-repo
tags: [user-testing, nextjs, turbopack, tailwind, dev-server, false-red]
---

## Anti-pattern

A worker switches the user's checkout to the feature branch while the dev
server keeps running. The UT validator then measures
`getComputedStyle(row, '::before').backgroundColor` and gets `rgba(0,0,0,0)`
because `.before\:bg-difficulty-*` was never generated into the served CSS
chunk. The served chunk still held main's `.before\:bg-win/arcane/gold`, even
though the source no longer contained them. After a plain restart it still did.

## What to do instead

- Before a UT run on a dev server, after any checkout change: stop the server,
  `rm -rf .next/dev`, start it again.
- Triage a styling red by fetching the served CSS chunk and grepping for the new
  class before opening a follow-up. If the class is absent while the source has
  it, the environment is stale, not the code.
- Keep workers out of the checkout the dev server runs from (fresh `/tmp`
  clone); fast-forward that checkout yourself and clear the cache in one step.

## Origin

[post-mortem](../../missions/2026-09-30-extract-overlay-dedicated-repo/post-mortem.md), feature F009.
