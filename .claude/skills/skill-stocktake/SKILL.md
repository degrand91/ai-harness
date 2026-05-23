---
name: skill-stocktake
description: Audit all registered skills in .claude/skills/ and return a structured inventory. Lists each skill by name, its argument hint, allowed tools, and whether its SKILL.md has valid frontmatter. Use during harness maintenance or before planning to understand available slash-commands.
argument-hint: "[--verbose]"
allowed-tools: Read, Bash(ls *), Bash(find *), Bash(head *), Bash(grep *)
disable-model-invocation: true
---

<!--
Ported from ECC (https://github.com/affaan-m/ECC)
Original: skills/skill-stocktake/SKILL.md
Copyright (c) 2026 Affaan Mustafa — Licensed under MIT
Note: ECC source was unreachable at port time; this is a minimal compatible implementation.
-->

## Goal

Produce a structured inventory of every skill registered in `.claude/skills/`.

---

## Procedure

### 1. Discover skill directories

```bash
find "${CLAUDE_PROJECT_DIR}/.claude/skills" -name "SKILL.md" | sort
```

### 2. For each SKILL.md, extract key fields

From the YAML frontmatter, extract:
- `name`
- `description`
- `argument-hint`
- `allowed-tools`
- `disable-model-invocation`

Use `grep` or `head` — do not execute the skill files.

### 3. Validate frontmatter shape

For each file, confirm:
- First line is exactly `---`
- A `name:` field is present
- The `name:` value matches the parent directory name

Mark any file that fails these checks as `INVALID`.

### 4. Output the inventory

Return a Markdown table:

```markdown
## Skill Inventory

| Skill | Description (truncated to 80 chars) | Argument hint | Allowed tools | Status |
|-------|--------------------------------------|---------------|---------------|--------|
| skill-stocktake | Audit registered skills... | [--verbose] | Read, Bash | OK |
| ... | ... | ... | ... | ... |
```

If `$ARGUMENTS` contains `--verbose`, also print the full `description` and `allowed-tools` values for each skill below the table.

### 5. Summary line

End with:

```
Total: N skills. Invalid: M.
```

---

## Anti-patterns

- Do not modify any skill file.
- Do not invoke any other skill — this is an audit tool only.
- Do not recurse outside `.claude/skills/`.
