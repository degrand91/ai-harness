# Integrations Schema

This document describes the structure of `integrations.json` at the project root.
Agents consult this file to discover optional external services and their configuration.

---

## File Location

```
integrations.json   (project root)
```

---

## Top-Level Structure

```json
{
  "$schema": "See templates/integrations-schema.md",
  "integrations": [ ... ]
}
```

| Field          | Type   | Description                                      |
|----------------|--------|--------------------------------------------------|
| `$schema`      | string | Reference to this document                       |
| `integrations` | array  | Ordered list of integration objects              |

---

## Per-Integration Fields

Each object in the `integrations` array must include all of the following fields:

| Field          | Type    | Required | Description                                                              |
|----------------|---------|----------|--------------------------------------------------------------------------|
| `id`           | string  | yes      | Unique slug identifier (kebab-case, lowercase)                           |
| `name`         | string  | yes      | Human-readable display name                                              |
| `type`         | string  | yes      | Service category — see Type Enum below                                   |
| `provider`     | string  | yes      | Vendor or platform name (e.g. `openai`, `google`, `lemonfox`)            |
| `enabled`      | boolean | yes      | `false` by default; set `true` to activate when env vars are present     |
| `description`  | string  | yes      | One-sentence description of what the integration does                    |
| `env_vars`     | object  | yes      | Map of environment variable names to metadata objects (see below)        |
| `endpoint`     | string  | yes      | Primary API endpoint URL                                                 |
| `capabilities` | array   | yes      | List of capability strings (e.g. `generate`, `edit`, `text-to-speech`)  |
| `usage`        | object  | yes      | Runnable example and cost information (see below)                        |
| `docs_url`     | string  | yes      | Official documentation URL                                               |

---

## The `env_vars` Object

Keys are environment variable names (UPPER_SNAKE_CASE). Each value is an object:

```json
"env_vars": {
  "OPENAI_API_KEY": {
    "required": true,
    "description": "OpenAI API key (starts with sk-)"
  }
}
```

| Field         | Type    | Description                                        |
|---------------|---------|----------------------------------------------------|
| `required`    | boolean | Whether the integration cannot function without it |
| `description` | string  | What the variable is and where to obtain it        |

---

## The `usage` Object

```json
"usage": {
  "command": "curl -s -H 'Authorization: Bearer $VAR_NAME' ...",
  "output_format": "JSON with url field",
  "cost_per_call": "~$0.04 per image"
}
```

| Field           | Type   | Description                                                    |
|-----------------|--------|----------------------------------------------------------------|
| `command`       | string | A runnable shell command using env var references (no secrets) |
| `output_format` | string | What shape the response takes                                  |
| `cost_per_call` | string | Indicative cost; use "Free" or "Unknown" when not applicable   |

---

## Type Enum

Valid values for the `type` field:

| Value   | Meaning                                              |
|---------|------------------------------------------------------|
| `image` | Image generation, editing, or manipulation           |
| `audio` | Text-to-speech, speech-to-text, or audio processing  |
| `video` | Video generation or editing                          |
| `text`  | Language model completions or embeddings             |
| `code`  | Code generation or execution environments            |
| `data`  | Data retrieval, search, or external databases        |

---

## How to Add a New Integration

1. Copy an existing entry from the `integrations` array in `integrations.json`.
2. Change all fields to match the new service.
3. Set `"enabled": false` — users opt in by setting it to `true` and supplying the env vars.
4. Use env var references (e.g. `$MY_API_KEY`) in `usage.command` — never paste real credentials.
5. Add the new env var name(s) to `env_vars` with `required` and `description`.
6. Update `docs_url` to the real documentation page.

---

## Security Note

**Never store real API keys, tokens, or secrets in `integrations.json`.**

- All keys belong in environment variables or a secret manager.
- Use references such as `$OPENAI_API_KEY` in `usage.command` examples.
- Commit this file freely — it contains no credentials.
- The harness contract (C-004) actively checks for patterns matching real keys and will fail if any are found.
