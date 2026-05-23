---
name: mission-list
description: List all harness missions with their state and current feature. Read-only. Cheap.
allowed-tools: Bash(ls *), Bash(jq *), Bash(cat *)
---

## Missions
!`for d in ${CLAUDE_PROJECT_DIR}/missions/*/; do [ -d "$d" ] || continue; id=$(basename "$d"); [ "$id" = ".gitkeep" ] && continue; state=$(jq -r '.state // "unknown"' "$d/status.json" 2>/dev/null); cur=$(jq -r '.current_feature // "—"' "$d/status.json" 2>/dev/null); n_feats=$(jq -r '.features | length' "$d/status.json" 2>/dev/null); echo "$id  state=$state  current=$cur  features=$n_feats"; done`

---

Summarise the missions above in a tidy table for the user. Columns: id, state, current feature, total features, age (since `started_at`).

Read-only skill. Do not write any files.
