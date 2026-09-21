---
name: lazy-chunk-asserted-by-size-only
description: A contract that checks "the heavy code is a separate chunk under N KB" passes even when that chunk is statically imported by every entry — bundlers emit modulepreload links and static imports for chunks created by manualChunks. Assert the module graph (no modulepreload/static import from entries) and the network (no request before the user action), not just bytes per file name.
introduced_in_mission: 2026-09-19-overlay-replay-import
tags: [contract, bundling, vite, performance]
---

## Anti-pattern

C-606 summed gzip sizes per file name (`/replay|w3g/i` → "replay", else "main") and passed on the first build. Scrutiny found `<link rel="modulepreload" href="./assets/replay-*.js">` in **both** HTML entries and a static `import "./replay-*.js"` in the picker entry — an 85 KB parser loaded eagerly on a window that never uses it. Cause: `vite-plugin-node-polyfills` injects global shims as static imports into every entry and merges its `globals` defaults under the user's object (omitting the key still enables them); `manualChunks` then dragged the whole bucket along.

## What to do instead

A `check:bundle` script that fails on: any `dist/*.html` referencing the chunk via `<script src>`/`modulepreload`; any non-lazy chunk containing a static `import"./<chunk>-`; the chunk's unique marker string appearing elsewhere. Pair it with a browser assertion: zero requests for the chunk before the triggering click, one after. Both are now in the overlay repo (`apps/overlay/scripts/check-bundle.mjs`).

## Origin

`missions/2026-09-19-overlay-replay-import/features/002-replay-import-ui/scrutiny.md`.
