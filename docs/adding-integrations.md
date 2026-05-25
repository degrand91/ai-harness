# Adding Integrations

A practical guide for connecting a new external service to the harness.

---

## Overview

`integrations.json` at the project root is the harness registry of optional external
services — image generators, audio APIs, translation engines, and so on. Agents read
this file to discover what services are available, how to call them, and whether the
required credentials are present. Nothing is enabled by default; you opt in explicitly.

The registry is committed to git and contains **no secrets**. It only holds env var
names and runnable curl templates that reference those names.

---

## Prerequisites

Before you add an entry, have the following ready:

- **API key** — obtained from the provider. You will not paste it into the JSON; you
  will name the env var that holds it.
- **Endpoint URL** — the primary REST endpoint you will call.
- **Docs URL** — the official API reference page. Agents use this to look up parameters.
- **A working curl command** — test it manually in your terminal before writing the
  entry. If the curl fails, fix it first.

---

## Step-by-Step Walkthrough

### Step 1 — Choose an ID

Pick a unique kebab-case slug that names the provider and the capability:

```
elevenlabs-tts
replicate-image
deepl-translate
aws-transcribe
```

Run this to confirm the ID is not already taken:

```bash
jq '.integrations[].id' integrations.json
```

### Step 2 — Determine the type

Pick the single value that best matches the service:

| Value   | When to use                                        |
|---------|----------------------------------------------------|
| `image` | Image generation, editing, or manipulation         |
| `audio` | Text-to-speech, speech-to-text, audio processing   |
| `video` | Video generation or editing                        |
| `text`  | Language model completions or embeddings           |
| `code`  | Code generation or execution environments          |
| `data`  | Data retrieval, search, or external databases      |

### Step 3 — Identify required env vars

List every credential or config value the API needs. Use UPPER_SNAKE_CASE. The harness
convention is `<PROVIDER>_API_KEY` for keys:

```
ELEVENLABS_API_KEY
REPLICATE_API_TOKEN
DEEPL_AUTH_KEY
```

Mark each one `required: true` unless the service genuinely works without it.

### Step 4 — Write the entry in `integrations.json`

Open `integrations.json` and append a new object to the `integrations` array. Always
set `enabled: false` when first adding — users activate it after confirming the env var
is set.

```json
{
  "id": "elevenlabs-tts",
  "name": "ElevenLabs Text-to-Speech",
  "type": "audio",
  "provider": "elevenlabs",
  "enabled": false,
  "description": "Convert text to natural-sounding speech using ElevenLabs voices.",
  "env_vars": {
    "ELEVENLABS_API_KEY": {
      "required": true,
      "description": "ElevenLabs API key from https://elevenlabs.io/app/settings/api-keys"
    }
  },
  "endpoint": "https://api.elevenlabs.io/v1/text-to-speech",
  "capabilities": ["text-to-speech", "voice-cloning"],
  "usage": {
    "command": "curl -s -X POST -H 'xi-api-key: $ELEVENLABS_API_KEY' -H 'Content-Type: application/json' -d '{\"text\":\"<TEXT>\",\"model_id\":\"eleven_monolingual_v1\",\"voice_settings\":{\"stability\":0.5,\"similarity_boost\":0.5}}' 'https://api.elevenlabs.io/v1/text-to-speech/<VOICE_ID>' --output speech.mp3",
    "output_format": "Binary audio file (mp3)",
    "cost_per_call": "~$0.30 per 1000 characters (Starter plan)"
  },
  "docs_url": "https://elevenlabs.io/docs/api-reference/text-to-speech"
}
```

### Step 5 — Test with the `/integrations` skill

Run the skill to confirm the entry parses correctly and appears in the table:

```bash
# In a Claude Code session:
/integrations
```

Or inspect directly:

```bash
jq '.integrations[] | select(.id == "elevenlabs-tts")' integrations.json
```

### Step 6 — Verify the env var is set

When you are ready to actually use the integration, set the env var and flip `enabled`
to `true`:

```bash
export ELEVENLABS_API_KEY="your-key-here"
test -n "$ELEVENLABS_API_KEY" && echo "set" || echo "missing"
```

Then update the entry:

```json
"enabled": true
```

---

## Complete Example: Replicate Image Generation

Replicate hosts many image models (Flux, SDXL, etc.) behind a single API.

```json
{
  "id": "replicate-image",
  "name": "Replicate Image Generation",
  "type": "image",
  "provider": "replicate",
  "enabled": false,
  "description": "Run open-source image generation models (Flux, SDXL, etc.) via the Replicate API.",
  "env_vars": {
    "REPLICATE_API_TOKEN": {
      "required": true,
      "description": "Replicate API token from https://replicate.com/account/api-tokens"
    }
  },
  "endpoint": "https://api.replicate.com/v1/predictions",
  "capabilities": ["generate", "inpaint", "upscale"],
  "usage": {
    "command": "curl -s -X POST -H 'Authorization: Bearer $REPLICATE_API_TOKEN' -H 'Content-Type: application/json' -d '{\"version\":\"black-forest-labs/flux-schnell\",\"input\":{\"prompt\":\"<PROMPT>\",\"num_outputs\":1}}' https://api.replicate.com/v1/predictions",
    "output_format": "JSON with urls[] field; poll the returned url until status is succeeded",
    "cost_per_call": "~$0.003 per image (Flux Schnell)"
  },
  "docs_url": "https://replicate.com/docs/reference/http"
}
```

Add this block inside the `integrations` array in `integrations.json`, then commit:

```bash
git add integrations.json
git commit -m "feat(integrations): add replicate-image integration"
```

---

## Field Reference

| Field           | Type    | Required | Notes                                                        |
|-----------------|---------|----------|--------------------------------------------------------------|
| `id`            | string  | yes      | Unique kebab-case slug — must not conflict with existing IDs |
| `name`          | string  | yes      | Human-readable display name                                  |
| `type`          | string  | yes      | One of: image, audio, video, text, code, data                |
| `provider`      | string  | yes      | Vendor name in lowercase (e.g. `openai`, `replicate`)        |
| `enabled`       | boolean | yes      | Start with `false`; set `true` only when env var is present  |
| `description`   | string  | yes      | One sentence — what the integration does                     |
| `env_vars`      | object  | yes      | Keys are env var names; values have `required` + `description` |
| `endpoint`      | string  | yes      | Primary API endpoint URL (HTTPS only)                        |
| `capabilities`  | array   | yes      | Capability strings, e.g. `["generate", "edit"]`              |
| `usage.command` | string  | yes      | Runnable curl using `$VAR_NAME` references — no real secrets |
| `usage.output_format` | string | yes | Describe the response shape                              |
| `usage.cost_per_call` | string | yes | Indicative cost; use "Free" or "Unknown" if not known    |
| `docs_url`      | string  | yes      | Official API docs URL                                        |

---

## Tips

**Always start with `enabled: false`.**
The registry is committed to git and shared across environments. A new entry should
never activate silently in a CI or team member's environment.

**Never put real API keys in the JSON.**
Use env var name references only (`$ELEVENLABS_API_KEY`, not `sk-abc123...`). The harness
contract C-004 scans for credential patterns and fails hard on any hit.

**Include a copy-paste curl in `usage.command`.**
Replace placeholder tokens with the real values when testing, then revert to the
placeholder form (`<PROMPT>`, `<TEXT>`) before committing. Another developer should be
able to copy the command, set the env var, and run it immediately.

**Test the curl manually before adding the entry.**
A broken command in `usage.command` misleads every agent that picks it up. Test first,
then write the entry.

**HTTPS only.**
Never add an integration with a plain `http://` endpoint. The protocol enforces HTTPS
for all integrations.

**Add the docs URL.**
Agents use `docs_url` to look up parameters and authentication details without leaving
the session. A missing or incorrect URL forces them to guess.

---

## Using Integrations in Missions

When a mission requires an integration, declare it in the contract preamble and add
a contract assertion that verifies the `enabled` flag and the env var before any
implementation work begins.

See [protocols/integrations.md](../protocols/integrations.md) for the full availability
check protocol and the exact jq commands workers run at feature start.
