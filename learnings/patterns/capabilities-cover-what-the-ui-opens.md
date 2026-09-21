---
name: capabilities-cover-what-the-ui-opens
description: In Tauri (and any capability/ACL-scoped host), unit tests that mock the host cannot see permission gaps — for every feature that opens a URL, reads a path, or invokes a plugin, the scrutiny step must diff the capability allow-list against the literal URLs/paths in the code, and a check script should enforce it structurally.
introduced_in_mission: 2026-09-20-overlay-auto-update
tags: [tauri, security, capabilities, scrutiny, testing]
---

## Pattern

The update banner's "Download" and "Releases" buttons called `host.openExternal(<github releases url>)`. All unit tests passed (they mock the host); the browser-mode user test passed (no ACL there). Scrutiny compared the opener allow-list (`vercel.app`, `discord.*`) with the URL constants in `config.ts` and found the buttons would be rejected silently in the native app. Fix: add the narrowest prefix to the allow-list **and** a `check:config` rule that extracts every URL literal the app opens and asserts an allow entry matches it — so the next feature cannot regress it.

Generalise: for each new host call (open URL, read/write path, HTTP fetch via plugin, shell), list the concrete targets in the spec, and make the config check enforce coverage. Mocked tests prove logic, not permission.

## Origin

`missions/2026-09-20-overlay-auto-update/features/002-in-app-update-flow/scrutiny.md`. Related: the macOS replay-folder scope gap in `2026-09-19-overlay-replay-import` (same class: `$DATA/Blizzard/**`).
