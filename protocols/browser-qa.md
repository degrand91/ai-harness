# Protocol: Browser-Based QA Validation

## When this applies

- Features with user-observable web behavior declared in the contract.
- The orchestrator spawns a User-Testing Validator for these features.

## Prerequisites

- Playwright MCP server configured in `.mcp.json` at project root.
- Node.js 18+ and npx available (verify with `scripts/setup-browser-qa.sh`).
- The target application must boot and serve HTTP.

## How it works

- The User-Testing Validator uses Playwright MCP tools to drive a real browser.
- Tools available: `browser_navigate`, `browser_click`, `browser_fill`, `browser_type`, `browser_screenshot`, `browser_snapshot`, `browser_select_option`, `browser_hover`, `browser_press_key`.
- The validator follows the contract's user-facing assertions, performing each flow end-to-end.

## Typical workflow

1. Boot the application using the launch recipe from the contract.
2. `browser_navigate` to the target URL.
3. `browser_snapshot` to understand page structure.
4. Interact: `browser_fill`, `browser_click`, `browser_select_option`, `browser_type`.
5. `browser_screenshot` at decisive moments → store under `features/NNN/evidence/`.
6. `browser_snapshot` to verify outcome (success messages, error states, URL changes).
7. Repeat for each user-facing assertion.

## Evidence standards

- Screenshots at decisive steps (before and after key interactions).
- Screenshots at responsive breakpoints (375px, 768px, 1440px) when contract demands.
- Accessibility snapshots for ARIA/keyboard validation.
- Evidence files stored under `features/NNN/evidence/` with systematic naming.

## Anti-patterns

- Using DevTools or direct API calls instead of browser interaction.
- Skipping the boot step.
- Capturing only happy-path evidence.
- Using Bash `curl` instead of browser tools for web UI testing.
- Mocking browser behavior.

## References

- Agent definition: `.claude/agents/user-testing-validator.md`
- Skill with patterns: `.claude/skills/browser-qa/SKILL.md`
- MCP configuration: `.mcp.json`
- Setup verification: `scripts/setup-browser-qa.sh`
