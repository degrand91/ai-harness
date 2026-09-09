#!/usr/bin/env python3
"""render.py - turn a crewmate's stream-json into something a human can watch.

Reads stream-json on stdin, appends every raw line to the file given as argv[1],
and prints a compact human line to stdout.

WHY THIS EXISTS. The whole point of the backend window is to watch a crewmate
work. run.sh originally tee'd the raw stream to a file and printed nothing, so
the window — and the log the backend tees into it — were empty. The first real
tmux run showed a pane containing only "Pane is dead".

WHY PYTHON AND NOT BASH. The obvious bash version used `python3 - <<'PY'`, and
the heredoc carrying the program IS stdin — so the stream never reached it and
the renderer silently produced nothing. A real script keeps stdin free.
"""
import json
import sys


def main() -> int:
    if len(sys.argv) < 2:
        print("render.py: raw output path required", file=sys.stderr)
        return 2

    raw = open(sys.argv[1], "a", buffering=1)

    def out(s: str) -> None:
        sys.stdout.write(s + "\n")
        sys.stdout.flush()

    for line in sys.stdin:
        raw.write(line)
        line = line.strip()
        if not line:
            continue
        try:
            o = json.loads(line)
        except Exception:
            continue

        kind = o.get("type")

        if kind == "system" and o.get("subtype") == "init":
            out(f"· session {o.get('session_id', '?')}  model {o.get('model', '?')}")

        elif kind == "assistant":
            for c in (o.get("message") or {}).get("content") or []:
                if c.get("type") == "text":
                    txt = (c.get("text") or "").strip()
                    if txt:
                        out("  " + txt[:400])
                elif c.get("type") == "tool_use":
                    inp = c.get("input") or {}
                    detail = inp.get("command") or inp.get("file_path") or inp.get("pattern") or ""
                    out(f"→ {c.get('name', '?')} {str(detail)[:120]}")

        elif kind == "user":
            for c in (o.get("message") or {}).get("content") or []:
                if c.get("type") == "tool_result" and c.get("is_error"):
                    out(f"  !! {str(c.get('content'))[:160]}")

        elif kind == "result":
            u = o.get("usage") or {}
            out("─" * 60)
            out(
                f"· {'error' if o.get('is_error') else 'finished'}"
                f"  turns {o.get('num_turns', '?')}"
                f"  tokens {u.get('input_tokens', 0)}/{u.get('output_tokens', 0)}"
                f"  ${o.get('total_cost_usd', 0):.4f}"
            )
            res = (o.get("result") or "").strip()
            if res:
                out("  " + res[:400])

    raw.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
