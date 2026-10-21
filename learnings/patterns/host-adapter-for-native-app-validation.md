---
name: host-adapter-for-native-app-validation
description: For a native/desktop app (Tauri, Electron, or similar) put every platform call behind a small host interface with a browser implementation and an env-gated selftest hook, so validators on a machine that cannot run the target OS still exercise real behaviour in a real browser and read native window/shortcut state from inside the runtime.
introduced_in_mission: private
tags: [planning, contract, validator, native, tauri, browser]
---

## Pattern

When the deliverable is a native window app but the harness runs on a machine that cannot run the target (macOS here, a Windows-only desktop target there), design for testability at plan time: (1) a `host` interface (`showWindow`, `hideWindow`, `startDragging`, `registerShortcuts`, `notifyStateChanged`, `openExternal`, window-bounds getters/setters) with a **Tauri implementation and a browser implementation** chosen at import time (`"__TAURI_INTERNALS__" in window`); browser mode maps global shortcuts to `keydown`, window hide/show to a `data-hidden` attribute, and cross-window events to `BroadcastChannel`. (2) An **env-gated selftest** (`<APP>_SELFTEST=1` → Rust command reads the env, frontend prints one JSON line per registered shortcut and per window's live flags via the runtime's own getters, then exits) — a no-op otherwise. The contract then splits cleanly: browser-behavioural assertions (Playwright against `vite preview`), native assertions (binary launches, selftest lines), and a short manual checklist for the real OS.

## Origin

A mission on a private project; the post-mortem stays local. Every UI assertion (C-014–C-016, C-020, C-023) was verified by user-testing validators in Chromium; native flags (C-024/C-025) came from the selftest, not from `osascript`/System Events, which proved unreliable for an unbundled debug binary. Two real bugs (a frozen clock from `useSyncExternalStore` snapshot equality; a first-`step_next` that skipped step 1) were caught in browser mode — they would have shipped in a "test it on Windows later" plan.

## Caveats

- Browser-mode key matching must use `event.code`/un-shifted keys, otherwise `Ctrl+Shift+]` arrives as `}` and only synthetic tests pass.
- On macOS the browser build maps `CommandOrControl` to Meta — say so in the contract so validators press Cmd.
- The selftest is a test-only surface: gate the exit command on the same env check so it cannot be invoked in normal runs.
