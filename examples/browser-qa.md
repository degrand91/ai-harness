# Example: Browser QA — Google Search + Contact Form Fill

A worked example of a browser QA mission using Playwright MCP. This covers: configuring the MCP
server, writing a contract with behavioral assertions, and validating a real user journey from a
Google search through to a contact form submission.

This is **descriptive**, not prescriptive. The real protocol lives in [CLAUDE.md](../CLAUDE.md).

---

## Scenario

**User:** "Open Google, search for stefano.puffapps.com, navigate to the site from the results,
then fill and submit the contact form. Capture screenshots at every decisive step as evidence."

---

## Prerequisites

Before any feature work begins:

- **`.mcp.json`** in the project root must declare the Playwright MCP server:
  ```json
  {
    "mcpServers": {
      "playwright": {
        "command": "npx",
        "args": ["@playwright/mcp@latest"]
      }
    }
  }
  ```
- **Node.js 18+** must be available in the shell (`node --version`).
- **`scripts/setup-browser-qa.sh`** passes exit 0 — the script verifies that the Playwright MCP
  server can launch and that a headless browser opens successfully.

---

## Contract snapshot

**`missions/2026-05-24-browser-qa-demo/contract.md` (excerpt)**

```markdown
## Assertions

C-001  exit 0      browser_navigate → https://www.google.com (page loads without error)
C-002  behavioral  Search results page shows a link containing "stefano.puffapps.com"
C-003  behavioral  Navigating to stefano.puffapps.com loads the site; contact section
                   is reachable at the #contact anchor
C-004  behavioral  Contact form on the page has fields: name, email, subject, message
                   and a submit button labelled "send message"
C-005  behavioral  Filling and submitting the form shows a success confirmation
                   (the #message element receives class "success")
C-006  exit 0      grep -rn "api_key\|secret\|token\|password\|credential" missions/ \
                       --include="*.md" | grep -v "C-006" | wc -l | grep -q "^0$"
```

---

## Feature loop walkthrough

This mission fits in a single feature: **F001 — browser-qa-contact-form**.

The Orchestrator spawns a **User-Testing Validator** (not a Worker — there is no code to write).
The Validator receives the contract slice and a launch recipe: start the Playwright MCP server,
run the journey, save evidence.

### Step-by-step Playwright MCP tool calls

**1. Open Google**

```
browser_navigate("https://www.google.com")
```

Wait for the page to reach a ready state. Then take a screenshot for evidence:

```
browser_screenshot → evidence/01-google-home.png
```

**2. Search for the site**

Locate the Google search input. On google.com the primary search box carries `name="q"`:

```
browser_fill('[name="q"]', "stefano.puffapps.com")
browser_press_key("Enter")
```

**3. Assert the result appears**

Take a DOM snapshot to find the result link without relying on pixel position:

```
browser_snapshot
```

The snapshot output should contain an element whose accessible text or URL includes
`stefano.puffapps.com`. This satisfies **C-002**. Then capture evidence:

```
browser_screenshot → evidence/02-search-results.png
```

**4. Navigate to the site from the results**

Click the result link. Google result links often wrap the domain; use a text or URL selector:

```
browser_click('a[href*="puffapps.com"]')
```

If the click opens a new tab, use `browser_navigate` directly as a fallback:

```
browser_navigate("https://stefano.puffapps.com")
```

Capture the landing page:

```
browser_screenshot → evidence/03-puffapps-landing.png
```

**5. Navigate to the contact section**

The site is a single-page Next.js app. The contact form lives at the `#contact` anchor on the
main page — there is no separate contact URL. Scroll to it via navigation:

```
browser_navigate("https://stefano.puffapps.com/#contact")
```

Take a snapshot to confirm the form fields are present (satisfies **C-003** and **C-004**):

```
browser_snapshot
```

The snapshot should reveal: `input[name="name"]`, `input[name="email"]`,
`input[name="subject"]`, `textarea[name="message"]`, and a button with text "send message".

Capture the empty form state:

```
browser_screenshot → evidence/04-contact-form-empty.png
```

**6. Fill the contact form**

The form element has `id="contactform"`. Fill each field by name:

```
browser_fill('input[name="name"]',    "Harness QA Bot")
browser_fill('input[name="email"]',   "qa@example.com")
browser_fill('input[name="subject"]', "Automated QA test")
browser_fill('textarea[name="message"]',
  "This message was sent by the harness browser-qa validator. Please ignore.")
```

Capture the filled state:

```
browser_screenshot → evidence/05-contact-form-filled.png
```

**7. Submit the form**

```
browser_click('button[type="submit"]')
```

**8. Assert success**

After submission the site renders a confirmation inside `#message` with class `success`.
Take a final snapshot to verify the element is present and visible (satisfies **C-005**):

```
browser_snapshot
```

Confirm the snapshot contains an element matching `#message.success` or the visible text of the
confirmation. Then capture the final screenshot as durable evidence:

```
browser_screenshot → evidence/06-form-submitted.png
```

---

## Evidence listing

The Validator stores all screenshots under the feature's evidence folder:

```
missions/2026-05-24-browser-qa-demo/features/001-browser-qa-contact-form/evidence/
  01-google-home.png
  02-search-results.png
  03-puffapps-landing.png
  04-contact-form-empty.png
  05-contact-form-filled.png
  06-form-submitted.png
```

Each file is referenced in `scrutiny.md` alongside the contract assertion it satisfies.

---

## Lessons reinforced by this shape

- **Browser tools enable real-user validation without mocking.** The Playwright MCP server drives
  an actual browser, so the QA journey catches rendering issues, JavaScript errors, and network
  failures that unit tests cannot.
- **`browser_snapshot` is for assertions; `browser_screenshot` is for evidence.** Use snapshots
  to inspect the accessibility tree and confirm element presence before acting. Use screenshots
  to capture durable visual proof that auditors and the Orchestrator can review later.
- **Capture evidence at every decisive step.** One screenshot per meaningful state transition —
  page load, search results, landing, empty form, filled form, submission — makes it easy to
  pinpoint exactly where a regression was introduced.
- **Reference the `/browser-qa` skill for more patterns.** The skill covers selector strategies,
  iframe handling, auth flows, and multi-tab scenarios that this example does not address.
