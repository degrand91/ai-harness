#!/usr/bin/env python3
"""harness.py - reading harness state without a delimiter protocol.

WHY THIS EXISTS. Four of the fifteen bugs found in this repo were the same
shape: hand-rolling a delimited-string protocol in bash and losing data at the
seam. Twice a tab (`IFS=$'\\t' read` collapses consecutive tabs, so an empty
field shifted every later field left), once a space (a list whose entries
contain spaces, split on spaces), once a heredoc that ate the stdin its own
program needed.

Batch readers — the ones that walk every mission and every project — do that
work here instead, reading files directly. No jq subprocesses, no field
separators, no quoting rules.

Bash keeps the hot paths: a hook that runs on every turn should not pay for a
Python interpreter. So state vocabulary has ONE owner
(scripts/lib/state-vocabulary.json) and two lookups, and
tests/state-vocabulary.test.sh asserts they agree on every entry.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

_HERE = Path(__file__).resolve().parent
_VOCAB = json.loads((_HERE / "state-vocabulary.json").read_text())

CANONICAL: list[str] = _VOCAB["canonical"]
TERMINAL: list[str] = _VOCAB["terminal"]


def load_json(path: Path) -> dict[str, Any] | None:
    """A file we cannot parse is None — never a default, never a guess."""
    try:
        d = json.loads(path.read_text())
        return d if isinstance(d, dict) else None
    except Exception:
        return None


def normalize_state(state: str, status: str, phase: str) -> str:
    """Canonical mission state, or 'unknown'.

    Mission files carry two vocabularies: the documented `.state`, and a drifted
    `.status` + `.phase`. Reading one and ignoring the other is what let a Stop
    guard report "all clear" on the only mission that was actually stuck.
    """
    if state in CANONICAL:
        return state
    if phase in _VOCAB["from_phase"]:
        return _VOCAB["from_phase"][phase]
    if status in _VOCAB["from_status"]:
        return _VOCAB["from_status"][status]
    return "unknown"


def mission_state(status_file: Path) -> str:
    d = load_json(status_file)
    if d is None:
        return "unknown"
    return normalize_state(
        str(d.get("state") or ""), str(d.get("status") or ""), str(d.get("phase") or "")
    )


def is_active(state: str) -> bool:
    """Unknown is NOT active: we cannot claim work is in flight when we cannot
    read the file. Callers that want to surface it do so explicitly."""
    return state not in TERMINAL and state != "unknown"


def mtime(path: Path) -> int:
    try:
        return int(path.stat().st_mtime)
    except OSError:
        return 0


def mission_last_activity(mission_dir: Path) -> int:
    return max(
        (mtime(mission_dir / n) for n in ("status.json", "log.md")),
        default=0,
    )


def missions_by_recency(missions_dir: Path) -> list[Path]:
    if not missions_dir.is_dir():
        return []
    out = []
    for d in missions_dir.iterdir():
        if not d.is_dir() or d.name.startswith("."):
            continue
        if not (d / "status.json").is_file():
            continue
        out.append(d)
    out.sort(key=mission_last_activity, reverse=True)
    return out


def open_holds(mission_dir: Path) -> int:
    """Answered holds MOVE to decisions/answered/, so counting open ones is a
    file count and costs nothing."""
    d = mission_dir / "decisions"
    if not d.is_dir():
        return 0
    return sum(1 for f in d.glob("*.json") if f.is_file())


def parse_registry(path: Path) -> list[dict[str, str]]:
    """`- <name> [<mode>[ +yolo]] <path> [allow="..."] - <desc> (added <date>)`

    Anything that is not a list line is prose and is ignored, so the file stays
    hand-editable. A malformed line is skipped here rather than guessed at;
    scripts/lib/registry.sh is the owner that reports it loudly.
    """
    if not path.is_file():
        return []
    out = []
    for line in path.read_text().splitlines():
        if not line.startswith("- "):
            continue
        rest = line[2:]
        name = rest.split(" ", 1)[0]
        if "[" not in rest or "]" not in rest:
            continue
        bracket = rest[rest.index("[") + 1 : rest.index("]")]
        yolo = "off"
        if bracket.endswith(" +yolo"):
            yolo, bracket = "on", bracket[: -len(" +yolo")]
        tail = rest[rest.index("]") + 1 :].split(" - ", 1)[0].strip()
        if not tail:
            continue
        allow = ""
        if 'allow="' in tail:
            allow = tail.split('allow="', 1)[1].split('"', 1)[0]
            tail = tail.split('allow="', 1)[0].strip()
        p = tail.strip()
        if p.startswith("~"):
            p = os.path.expanduser(p)
        out.append(
            {"name": name, "mode": bracket, "yolo": yolo, "path": p.rstrip("/"), "allow": allow}
        )
    return out
