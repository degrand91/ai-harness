#!/usr/bin/env python3
"""snapshot.py - the single owner of reading fleet state.

Replaces a 255-line bash script that orchestrated fourteen jq call sites and a
hand-rolled Unit-Separator field protocol. That protocol existed only because
bash cannot pass structured data around, and it is where two of this repo's
bugs lived: `IFS=$'\\t' read` collapsing empty fields, twice.

Reading the files directly removes the seam rather than hardening it. There is
no delimiter, no field order, no quoting rule, and no jq.

Six renderers used to parse status.json independently, which is how schema
drift went unnoticed in all six at once. Everything consumes this document now;
scripts/fleet.sh proves the pattern by parsing nothing itself.

Schema: {schema, generated_at, projects[], missions[], crew[], totals{}}
`schema` is an integer; bump it on any breaking change to this shape.
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import harness  # noqa: E402

SCHEMA = 1


def build(root: Path) -> dict:
    missions_dir = root / "missions"
    projects = harness.parse_registry(root / "data" / "projects.md")
    by_path = {p["path"]: p["name"] for p in projects}
    crew = harness.crew_tasks(root)

    missions = []
    for mdir in harness.missions_by_recency(missions_dir):
        sfile = mdir / "status.json"
        doc = harness.load_json(sfile)
        parsed = doc is not None
        doc = doc or {}

        state = harness.normalize_state(
            str(doc.get("state") or ""),
            str(doc.get("status") or ""),
            str(doc.get("phase") or ""),
        )

        target = str(doc.get("target_repo") or "")
        if target.startswith("~"):
            target = os.path.expanduser(target)
        project = by_path.get(target.rstrip("/")) if target else None

        # .tokens holds per-role objects; a scalar alongside them must not blank
        # the fleet, so non-objects are skipped rather than trusted.
        tk = doc.get("tokens") or {}
        roles = [v for v in tk.values() if isinstance(v, dict)] if isinstance(tk, dict) else []

        missions.append(
            {
                "id": mdir.name,
                "title": doc.get("title") or mdir.name,
                "state": state,
                "active": harness.is_active(state),
                "project": project,
                "last_activity": harness.mission_last_activity(mdir),
                "open_holds": harness.open_holds(mdir),
                "current_feature": doc.get("current_feature"),
                "parsed": parsed,
                "features": [
                    {
                        "id": f.get("id"),
                        "slug": f.get("slug"),
                        "state": f.get("state") or f.get("status"),
                        "color": f.get("color"),
                        # Written by crew teardown after a direct-PR delivery.
                        # Dropping it here would put the PR back out of reach.
                        "pr_url": f.get("pr_url"),
                        "followups": (
                            len(f["followups"]) if isinstance(f.get("followups"), list)
                            else (f.get("followups") or 0)
                        ),
                    }
                    for f in (doc.get("features") or [])
                    if isinstance(f, dict)
                ],
                "tokens": {
                    "input": sum(int(r.get("input") or 0) for r in roles),
                    "output": sum(int(r.get("output") or 0) for r in roles),
                },
                "cost_usd": doc.get("cost_usd") or 0,
            }
        )

    return {
        "schema": SCHEMA,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "projects": [
            {"name": p["name"], "mode": p["mode"], "yolo": p["yolo"], "path": p["path"]}
            for p in projects
        ],
        "missions": missions,
        "crew": crew,
        "totals": {
            "missions": len(missions),
            "active_missions": sum(1 for m in missions if m["active"]),
            "unparsed": sum(1 for m in missions if not m["parsed"]),
            "open_holds": sum(m["open_holds"] for m in missions),
            "tokens": {
                "input": sum(m["tokens"]["input"] for m in missions),
                "output": sum(m["tokens"]["output"] for m in missions),
            },
            "cost_usd": sum(m["cost_usd"] for m in missions),
            "crew": {
                "live": sum(1 for c in crew if c["alive"]),
                "total": len(crew),
            },
        },
    }


def main(argv: list[str]) -> int:
    pretty = False
    for a in argv[1:]:
        if a == "--pretty":
            pretty = True
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            print(f"snapshot: unknown option {a}", file=sys.stderr)
            return 2

    root = Path(os.environ.get("CLAUDE_PROJECT_DIR") or Path(__file__).resolve().parent.parent)
    doc = build(root)
    json.dump(doc, sys.stdout, indent=2 if pretty else None)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
