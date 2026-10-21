---
name: setup
description: One command to get the harness ready to use — checks required tools and state roots, reports per-skill capability dependencies (node, ffmpeg, python+playwright, the Playwright MCP, gh), and offers to install the missing optional ones. Use on a fresh clone, after vendoring new skills, or when a skill reports a missing dependency.
disable-model-invocation: true
argument-hint: (none) | --install
allowed-tools: Read, Bash
---

## Current readiness
!`bash "${CLAUDE_PROJECT_DIR}/scripts/setup.sh" --check 2>&1 || true`

---

You are helping the operator make this harness fully usable. The readiness report
above is `scripts/setup.sh --check` — it mutates nothing. Read it and act:

## 1. If everything is ready

If the report ends with "Ready — core and all optional capabilities are present",
say so in one line and stop. Nothing to do.

## 2. If core is NOT ready

If it says "NOT READY" (a required tool — git, jq, or bash — is missing), that is
the only blocking case. Tell the operator exactly which tool is missing and the
install command for their platform, and stop — nothing else matters until the
core tools exist.

## 3. If optional capabilities are missing

The report lists what each skill needs and what is absent (ffmpeg, python +
playwright, the Playwright MCP, gh auth, …). These are **per-skill** — the
harness core runs without them; a given skill only needs its own.

- Summarise, in plain language, which skills are **READY**, which are **PARTIAL**,
  and exactly what each partial one needs.
- Then **offer** to install the missing optional tools:
  - On a plain "go", run `scripts/setup.sh --install`. It installs **only**
    optional capability tools, via the detected package manager (winget / brew /
    apt / dnf / pacman / choco / scoop), echoing each command first, and never
    touches required tools.
  - If no package manager is detected, it prints the manual install commands
    instead — relay those and let the operator run them.
- **`gh auth` is always manual** — if gh is unauthenticated, tell the operator to
  run `gh auth login` themselves; never attempt it for them.
- After installing, it re-checks and prints what (if anything) is still missing.

## 4. Confirm

Re-run `bash scripts/setup.sh --check` and report the new state in a line or two:
which skills are now ready, and any capability still outstanding (with the reason
it could not be resolved — e.g. a tool that needs a shell restart to land on
PATH).

## Notes

- The operator can run the same thing outside a session: `scripts/setup.sh`
  (report) or `scripts/setup.sh --install` (install the optional tools).
- Installing software mutates the machine, so **never** run `--install` without an
  explicit go from the operator. `--check` is always safe.
- This does not configure projects — registering a delivery target is still
  `scripts/project.sh add` (see [protocols/project-registry.md](../../../protocols/project-registry.md)).
