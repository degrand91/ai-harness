# Protocol: Multi-provider Validation (v0.3)

## Why

The Creator-Verifier pattern gains its adversarial strength from isolation. If the Worker and the Scrutiny Validator share the same model, the same training data, and the same provider, the Validator can inherit Worker reasoning biases — they may share blind spots. Putting the Validator on a **different provider** gives the strongest possible independence: the Validator was not trained on the same data distribution, and its assessment is structurally uncorrelated with the Worker's output.

v0.3 ships the mechanism that enables this. The default path (Haiku, no external provider) is unchanged. The external-provider path is ready to configure; it is not exercised by default.

---

## The env var contract

```
HARNESS_EXTERNAL_VALIDATOR_PROVIDER
```

| State | Effect |
|-------|--------|
| Unset or empty | Orchestrator spawns `scrutiny-validator` (Haiku, no MCP). Default path. |
| Set to any non-empty string | Orchestrator spawns `scrutiny-validator-external` (external provider via MCP). |

**Where to set it:** operator shell environment, a project-local `.env` sourced before starting Claude Code, or the Claude Code session environment. The value is free-form — it serves as a human-readable label for the operator (e.g. `"openai"`, `"gemini"`, `"bedrock"`). The harness does not parse the value; it only tests for presence.

**Secret handling:** The env var itself is not a credential. MCP server credentials (API keys for the external provider) belong in the MCP server config inside `.claude/agents/scrutiny-validator-external.md`, not in this variable.

---

## The two-agent-file pattern

Two agent definition files ship with the harness:

| File | When active | Model | MCP |
|------|-------------|-------|-----|
| `.claude/agents/scrutiny-validator.md` | `HARNESS_EXTERNAL_VALIDATOR_PROVIDER` unset/empty | Haiku | None |
| `.claude/agents/scrutiny-validator-external.md` | `HARNESS_EXTERNAL_VALIDATOR_PROVIDER` set | External provider | `mcpServers:` block in frontmatter |

`scrutiny-validator.md` is the stable, default, always-works path. It requires no configuration.

`scrutiny-validator-external.md` ships with a commented `mcpServers:` block. The operator fills in their provider config. The file is included in the repo configured but un-exercised on machines without a provider available. _(This file is created in F003 of this mission; it is a forward reference here.)_

---

## Orchestrator routing rule

At scrutiny-spawn time, the Orchestrator inspects the env var and selects the agent file:

```bash
if [ -n "${HARNESS_EXTERNAL_VALIDATOR_PROVIDER}" ]; then
  SCRUTINY_AGENT="scrutiny-validator-external"
else
  SCRUTINY_AGENT="scrutiny-validator"
fi
```

Translated to the Agent tool call:

```
Agent({
  subagent_type: SCRUTINY_AGENT,   // "scrutiny-validator" or "scrutiny-validator-external"
  model: "haiku",                  // overridden by the external agent's frontmatter when relevant
  description: "Scrutiny — feature <slug>",
  prompt: <contract slice> + <diff>
})
```

The `model` field in the external agent's frontmatter takes precedence over the `model` parameter when Claude Code resolves the subagent. The Orchestrator should still set `model: "haiku"` as a safe fallback for the default path.

---

## What the external agent file ships with

`.claude/agents/scrutiny-validator-external.md` ships with:

1. The same role prompt and verdict format as `scrutiny-validator.md`.
2. A `mcpServers:` block in its YAML frontmatter, commented out by default:

```yaml
---
name: scrutiny-validator-external
model: haiku          # overridden per operator config
# mcpServers:
#   external-provider:
#     command: npx
#     args: ["-y", "@your-provider/mcp-server"]
#     env:
#       PROVIDER_API_KEY: "${PROVIDER_API_KEY}"
---
```

The operator fills in the real MCP server command and API key reference. Until then the file is inert.

---

## Fallback semantics

**If `HARNESS_EXTERNAL_VALIDATOR_PROVIDER` is unset or empty:**
- No MCP server connection is attempted.
- No error is raised.
- The default `scrutiny-validator` (Haiku) runs exactly as it did in v0.2.

This is the v0.3 exit criterion: the harness does not break on machines without an external provider. The external path is opt-in.

---

## What does NOT ship in v0.3

- A working end-to-end integration with a specific named external provider.
- Any tested MCP server configuration (no provider CLI available on the development machine).
- Automatic provider selection or round-robin.
- Cost reporting split by provider (planned for v0.4 post-mortem integration).

These are deferred to v0.3.1 or later when a concrete provider is available for testing.

---

## Cross-references

- [`protocols/model-routing.md`](model-routing.md) — routing table and provider-isolation context.
- [`.claude/agents/scrutiny-validator.md`](../.claude/agents/scrutiny-validator.md) — default Haiku validator.
- [`.claude/agents/scrutiny-validator-external.md`](../.claude/agents/scrutiny-validator-external.md) — external-provider validator (created in F003).
