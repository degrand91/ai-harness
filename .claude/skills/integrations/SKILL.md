---
name: integrations
description: Check available integrations and their status
---

# Skill: integrations

Invoke with `/integrations` to inspect what external service integrations are registered
and which are ready to use in the current environment.

---

## Steps

1. **Read `integrations.json`** at the project root.

2. **For each integration**, check:
   - Is `enabled` set to `true`?
   - For enabled integrations, is every required env var set?
     Run `test -n "$VAR_NAME"` for each name listed under `env_vars` where `required` is `true`.

3. **Output a table** with the following columns:

   | id | name | type | enabled | env vars |
   |----|------|------|---------|----------|
   | openai-image | OpenAI Image Generation | image | false | OPENAI_API_KEY: missing |
   | nanobanana | NanoBanana / Google Gemini Image Generation | image | false | GOOGLE_API_KEY: missing |
   | lemonfox-audio | LemonFox Audio (TTS + STT) | audio | false | LEMONFOX_API_KEY: missing |

   The "env vars" cell lists each required variable followed by `set` or `missing`.
   For disabled integrations, still check and report env var status — it helps diagnose
   why an integration was left disabled.

4. **Conclude** with a summary line:

   - List which integrations are **ready to use** (enabled AND all required env vars set).
   - List which are **disabled** (enabled: false).
   - List which are **misconfigured** (enabled: true but one or more required env vars missing).

---

## Example output

```
## Integration Status

| id             | name                                  | type  | enabled | env vars               |
|----------------|---------------------------------------|-------|---------|------------------------|
| openai-image   | OpenAI Image Generation               | image | false   | OPENAI_API_KEY: missing |
| nanobanana     | NanoBanana / Google Gemini Image Gen  | image | false   | GOOGLE_API_KEY: missing |
| lemonfox-audio | LemonFox Audio (TTS + STT)            | audio | false   | LEMONFOX_API_KEY: missing |

Ready to use:     none
Disabled:         openai-image, nanobanana, lemonfox-audio
Misconfigured:    none
```

---

## Notes

- Never print the value of an env var. Only report its name and whether it is set or missing.
- If `integrations.json` does not exist, output: `integrations.json not found at project root.`
- For full protocol details, see [protocols/integrations.md](../../protocols/integrations.md).
