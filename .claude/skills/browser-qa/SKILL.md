---
name: browser-qa
description: Playwright MCP testing patterns for the user-testing-validator
---

# Skill: browser-qa

## 1. Overview

This skill teaches the `user-testing-validator` agent (and any future QA agent) how to
validate user-observable behavior using the Playwright MCP browser tools.

**When to use this skill:**
- The feature has a user-observable flow (form submission, navigation, rendering)
- The contract slice requires screenshots as evidence
- The contract slice requires accessibility validation
- You need to verify error states, redirects, or multi-step wizard flows

**When NOT to use this skill:**
- Pure back-end or infrastructure changes with no UI surface
- Changes whose contract is fully satisfied by unit/integration tests

The MCP server is declared in `.mcp.json` under the key `"playwright"`. All tools
listed below are provided by that server. Call them directly by their tool name
(e.g. `browser_navigate`) — the harness wires the MCP namespace automatically.

---

## 2. Available browser tools

| Tool | Description |
|------|-------------|
| `browser_navigate` | Navigate the current tab to a URL |
| `browser_click` | Click an element identified by text, ARIA role, or CSS selector |
| `browser_type` | Type characters into the currently focused element |
| `browser_fill` | Fill a form field by label, placeholder, or selector |
| `browser_screenshot` | Capture a PNG screenshot of the current viewport |
| `browser_snapshot` | Return the full accessibility tree of the current page |
| `browser_select_option` | Select an option from a `<select>` dropdown |
| `browser_hover` | Hover over an element (triggers :hover styles and tooltips) |
| `browser_press_key` | Press a keyboard key (e.g. `Tab`, `Enter`, `Escape`) |
| `browser_wait` | Wait for a selector, URL, or network idle condition |
| `browser_tab_list` | List all open browser tabs |
| `browser_tab_new` | Open a new tab |
| `browser_tab_close` | Close a tab by index |

---

## 3. Form testing patterns

### Fill and submit a form

```
browser_navigate  url="http://localhost:3000/contact"
browser_fill      selector="#name"        value="Alice Tester"
browser_fill      selector="#email"       value="alice@example.com"
browser_fill      selector="#message"     value="Hello from QA"
browser_screenshot                          # capture before submit
browser_click     selector="button[type=submit]"
browser_wait      selector=".success-toast"
browser_screenshot                          # capture success state
```

### Verify success feedback

After submit, assert one of:
- A redirect occurred (inspect current URL with `browser_snapshot` — look for the `url` field)
- A success toast / banner is visible (`browser_wait selector=".toast--success"`)
- A confirmation message is present (`browser_snapshot` → inspect landmark text)

### Test empty/invalid form submission

```
browser_navigate  url="http://localhost:3000/contact"
browser_click     selector="button[type=submit]"           # submit without filling
browser_wait      selector="[aria-invalid=true]"           # HTML5 validation fired
browser_snapshot                                           # inspect error messages
browser_screenshot                                         # evidence
```

Confirm that at least one element carries `aria-invalid="true"` or an error message
element is visible (`[role=alert]`, `.field-error`, etc.).

### Test multi-step forms (wizard flows)

```
browser_navigate  url="http://localhost:3000/signup"
# Step 1
browser_fill      selector="#email"   value="bob@example.com"
browser_click     selector="text=Next"
browser_wait      selector="text=Step 2"
browser_screenshot                                         # step 2 visible
# Step 2
browser_fill      selector="#password"  value="S3cure!pw"
browser_click     selector="text=Create account"
browser_wait      url="**/dashboard"
browser_screenshot                                         # final destination
```

### Handle file upload fields

```
browser_navigate  url="http://localhost:3000/upload"
browser_fill      selector="input[type=file]"  value="/path/to/test-file.pdf"
browser_wait      selector=".upload-progress[aria-valuenow='100']"
browser_screenshot
```

### Test select/dropdown interactions

```
browser_navigate  url="http://localhost:3000/settings"
browser_select_option  selector="#country"  value="NL"
browser_screenshot                                         # confirm selection reflected
```

---

## 4. Navigation testing patterns

### Navigate and verify content loads

```
browser_navigate  url="http://localhost:3000/"
browser_wait      selector="h1"
browser_snapshot                                           # verify heading text
```

### Test link clicks and verify destination

```
browser_click     selector="text=About us"
browser_wait      url="**/about"
browser_snapshot                                           # check page title / heading
```

### Test back/forward navigation

```
browser_navigate  url="http://localhost:3000/page-a"
browser_navigate  url="http://localhost:3000/page-b"
browser_press_key key="Alt+ArrowLeft"                     # browser back
browser_wait      url="**/page-a"
browser_snapshot
```

### Verify URL changes after actions

Inspect the `url` field from `browser_snapshot` after each user action that is expected
to change the URL (form submit, tab click, filter selection).

### Test redirects

```
browser_navigate  url="http://localhost:3000/dashboard"   # protected route
browser_wait      url="**/login"                          # expect redirect to login
browser_screenshot
```

For post-submit redirects:

```
browser_click     selector="button[type=submit]"
browser_wait      url="**/thank-you"
browser_screenshot
```

---

## 5. Screenshot evidence patterns

### Capture at decisive steps

Take a screenshot before and after every meaningful action:
- Initial page load
- After filling the form (before submit)
- After submit (success or error state)
- After navigation to a new page

### Systematic naming convention

Name files with a zero-padded sequence prefix so they sort chronologically:

```
01-page-load.png
02-form-filled.png
03-submit-clicked.png
04-success-state.png
05-error-state.png
```

Store every screenshot under the feature's evidence folder:

```
missions/<id>/features/<n>/evidence/<name>.png
```

Pass the full absolute path as the `path` argument to `browser_screenshot`.

### Responsive / breakpoint screenshots

To validate responsive behavior, resize the viewport before each capture:

```
# Mobile (375 px)
browser_navigate  url="http://localhost:3000/"
# set viewport via MCP option if supported, or note default size
browser_screenshot  path=".../evidence/01-mobile-375.png"

# Tablet (768 px)
browser_screenshot  path=".../evidence/02-tablet-768.png"

# Desktop (1440 px)
browser_screenshot  path=".../evidence/03-desktop-1440.png"
```

---

## 6. Accessibility testing patterns

### Get the accessibility tree

```
browser_snapshot
```

The snapshot returns a structured tree of ARIA roles, names, states, and values.
Inspect it to verify:
- Every interactive element has an accessible name
- Form fields are labelled (`<label>` association or `aria-label`)
- Landmark regions are present (`main`, `nav`, `header`, `footer`)
- Error messages are associated with their fields (`aria-describedby`)

### Keyboard navigation

```
browser_navigate  url="http://localhost:3000/contact"
browser_press_key key="Tab"                               # move focus to first field
browser_press_key key="Tab"                               # advance to next field
browser_press_key key="Tab"                               # advance to submit button
browser_press_key key="Enter"                             # submit via keyboard
browser_wait      selector=".success-toast"
browser_snapshot                                          # verify focus management
```

Tab order should follow the visual reading order. Every interactive element must be
reachable and operable without a mouse.

### Verify ARIA attributes

After `browser_snapshot`, check the tree output for:
- `role="alert"` on dynamic error messages
- `aria-invalid="true"` on invalid fields
- `aria-expanded` toggling correctly on accordions / dropdowns
- `aria-label` or `aria-labelledby` on icon-only buttons

### Verify focus management

- On validation failure: focus should move to the first invalid field or to an error
  summary (`role="alert"`, `tabindex="-1"`)
- After a modal opens: focus should be trapped inside the modal
- After a modal closes: focus should return to the trigger element

---

## 7. Error state testing

### Network failure behavior

If the app has an offline mode or retry UI, simulate by navigating while offline is not
directly controllable via MCP. Instead:
- Point the app at a deliberately broken API base URL configured in test env
- Submit and assert that a user-visible error message appears (`role="alert"`)

### Authorization failures (expired session)

```
browser_navigate  url="http://localhost:3000/dashboard"   # unauthenticated
browser_wait      url="**/login"                          # verify redirect
browser_screenshot
```

For role-based access:
```
browser_navigate  url="http://localhost:3000/admin"
browser_wait      selector="text=403"                     # or appropriate error page
browser_screenshot
```

### Form validation errors

```
browser_navigate  url="http://localhost:3000/contact"
browser_fill      selector="#email"  value="not-an-email"
browser_click     selector="button[type=submit]"
browser_wait      selector="[aria-invalid=true]"
browser_snapshot                                          # inspect error message text
browser_screenshot
```

Assert that the error message text is visible and descriptive (not just a red border).

### Empty states (no data scenarios)

```
browser_navigate  url="http://localhost:3000/results?q=xyzzy-no-match"
browser_wait      selector=".empty-state"
browser_snapshot                                          # verify empty state message
browser_screenshot
```

The empty state must carry a human-readable message, not a blank screen.

---

## 8. Common recipes

### Recipe A — Login flow

```
browser_navigate  url="http://localhost:3000/login"
browser_screenshot  path=".../evidence/01-login-page.png"

browser_fill      selector="#email"     value="user@example.com"
browser_fill      selector="#password"  value="correct-password"
browser_screenshot  path=".../evidence/02-credentials-filled.png"

browser_click     selector="button[type=submit]"
browser_wait      url="**/dashboard"
browser_screenshot  path=".../evidence/03-dashboard.png"

browser_snapshot                                          # verify welcome heading
```

Pass criteria: URL is `/dashboard`, a heading or greeting containing the user name is
present in the accessibility tree.

### Recipe B — Contact form

```
browser_navigate  url="http://localhost:3000/contact"
browser_screenshot  path=".../evidence/01-contact-empty.png"

browser_fill      selector="#name"     value="QA Tester"
browser_fill      selector="#email"    value="qa@example.com"
browser_fill      selector="#message"  value="This is a test message from QA."
browser_screenshot  path=".../evidence/02-contact-filled.png"

browser_click     selector="button[type=submit]"
browser_wait      selector=".confirmation-message"
browser_screenshot  path=".../evidence/03-contact-submitted.png"

browser_snapshot                                          # verify confirmation text
```

Pass criteria: confirmation element is visible, no `aria-invalid` fields remain.

### Recipe C — Search flow

```
browser_navigate  url="http://localhost:3000/"
browser_fill      selector="input[type=search]"  value="harness"
browser_screenshot  path=".../evidence/01-search-query.png"

browser_press_key key="Enter"
browser_wait      selector=".search-results"
browser_screenshot  path=".../evidence/02-search-results.png"

browser_snapshot                                          # count result items
```

Pass criteria: at least one result item is present in the accessibility tree under the
results landmark.
