# Security Policy

## Supported Versions

This project uses a rolling release model. Only the latest version on `main` receives
security fixes. See [CHANGELOG.md](CHANGELOG.md) for the release history.

## Reporting a Vulnerability

**For sensitive disclosures** (proof-of-concept exploits, secrets in committed state,
permission bypass): use [GitHub Security Advisories](https://github.com/degrand91/ai-harness/security/advisories/new)
to open a private advisory. Do **not** post sensitive vulnerability details in public issues.

**For non-sensitive security concerns** (general hardening suggestions, documentation
gaps): open a GitHub Issue tagged `security`.

We will acknowledge receipt within 7 days and provide a timeline for resolution once
we have assessed the report.

## In-Scope Items

The following are in scope for vulnerability reports:

- **Prompt injection** in protocol files or agent definitions that could cause the
  harness to execute unintended commands.
- **Permission allowlist gaps** in `.claude/settings.json` that allow unintended tool
  access.
- **Secrets or credentials leaked** into committed mission state under `missions/`.
- **Hooks that fail open** when they should fail closed (e.g., a guard hook that exits 0
  on error instead of blocking).

## Out-of-Scope Items

The following are out of scope — please report them to the appropriate party instead:

- **Claude Code itself** → [Anthropic](https://www.anthropic.com/security)
- **MCP servers** → their respective maintainers
- **The LLM provider's API** → Anthropic or the relevant provider

## Responsible Disclosure

We ask that you give us reasonable time to address a vulnerability before any public
disclosure. We will work with you to coordinate a disclosure timeline.
