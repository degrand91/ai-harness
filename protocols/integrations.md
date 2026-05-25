# Integrations Protocol

This protocol governs how agents discover, check, and use external service integrations
registered in `integrations.json` at the project root.

---

## Purpose

The harness supports optional external service integrations (image generation, audio,
text, data, etc.). These integrations are configured centrally in `integrations.json`
so that any agent can discover what services are available without embedding service
details in mission specs or agent prompts.

Agents consult this protocol before making any call to an external service. The contract
preamble declares which integrations a mission requires. Workers verify availability
before proceeding.

---

## Discovery

Before using any external service, read `integrations.json` at the project root:

```bash
cat integrations.json | jq '.integrations[] | {id, name, type, enabled}'
```

Use the skill `/integrations` to get a formatted availability table.

---

## Checking Availability

Before using an integration, perform all four checks in order:

**Step 1 — Find the entry.**
```bash
jq '.integrations[] | select(.id == "<integration-id>")' integrations.json
```
If the entry does not exist, report a blocker in the handoff.

**Step 2 — Confirm it is enabled.**
```bash
jq -e '.integrations[] | select(.id == "<integration-id>" and .enabled == true)' integrations.json
```
Exit code 0 means enabled. Non-zero means the integration is disabled — report a blocker.

**Step 3 — Verify required environment variables are set.**

For each variable listed under `env_vars` where `required` is `true`, run:
```bash
test -n "$VAR_NAME"
```
If any required variable is unset or empty, report it by name in the handoff. Never log
or print the variable value — only its name.

**Step 4 — All checks green?**
If steps 1–3 all pass, the integration is ready to use. If any step fails, record the
failure in the handoff "Issues discovered" section and mark the feature blocked.

---

## Using an Integration

The `usage.command` field in `integrations.json` provides a runnable curl template.
Replace the placeholder tokens (e.g. `<PROMPT>`, `<TEXT>`) with actual runtime values:

```bash
# Example — OpenAI image generation
curl -s \
  -H 'Authorization: Bearer $OPENAI_API_KEY' \
  -H 'Content-Type: application/json' \
  -d '{"model":"dall-e-3","prompt":"a red apple","n":1,"size":"1024x1024"}' \
  https://api.openai.com/v1/images/generations
```

The env var is expanded by the shell at runtime — never hardcode a key value in the
command or in any committed file.

---

## Contract Integration

Missions that require specific integrations must declare them in the contract preamble:

```markdown
## Preamble
...
- Required integrations: openai-image (enabled), lemonfox-audio (enabled)
```

Each required integration must have at least one contract assertion (see the integration
assertion example in `templates/validation-contract.md`). The assertion must verify
both the `enabled` flag and the presence of required env vars.

Workers must check all declared integrations before beginning implementation. If an
integration is unavailable, the Worker records a blocker in the handoff and does not
attempt to call the service.

---

## Adding New Integrations

Follow the schema defined in `templates/integrations-schema.md`:

1. Copy an existing entry in the `integrations` array.
2. Assign a unique kebab-case `id`.
3. Set `"enabled": false` — users opt in explicitly.
4. Use env var references (`$MY_API_KEY`) in `usage.command`. Never paste credentials.
5. Fill all required fields: `id`, `name`, `type`, `provider`, `description`,
   `env_vars`, `endpoint`, `capabilities`, `usage`, `docs_url`.
6. Set `enabled: true` only after the env var is confirmed present in the target environment.

---

## Security

- Never log, print, or commit the value of an API key or token.
- Only reference the env var name (e.g. `OPENAI_API_KEY`) in logs, handoffs, and contracts.
- Harness contract C-004 actively scans for credential patterns; any hit is a hard failure.
- Consult `templates/integrations-schema.md` for the full security note.
- Integrations run over HTTPS endpoints only — never add an integration with a plain HTTP endpoint.

---

## Quick Reference

| Task | Command |
|------|---------|
| List all integrations | `/integrations` |
| Check one integration is enabled | `jq -e '.integrations[] \| select(.id == "X" and .enabled == true)' integrations.json` |
| Verify env var is set | `test -n "$VAR_NAME"` |
| View usage command | `jq -r '.integrations[] \| select(.id == "X") \| .usage.command' integrations.json` |
| View docs URL | `jq -r '.integrations[] \| select(.id == "X") \| .docs_url' integrations.json` |
