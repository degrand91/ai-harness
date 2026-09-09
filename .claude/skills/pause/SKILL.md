---
name: pause
description: Stop the autonomous loop on a mission because the captain is taking over. Use when they say stop, hold on, let me look, or otherwise want the harness to stop dispatching work.
argument-hint: [mission-id]
allowed-tools: Bash(./scripts/status.sh *), Bash(./scripts/fleet.sh), Read, Edit
---

Set the mission's `state` to `paused` in `missions/<id>/status.json`, then confirm in one line.

**Why this exists.** "Stop, I'll take over" ends a turn. Without a recorded pause, the turn-end guard sees an executing mission with pending work and refuses the stop, and the watcher's backstop would resume the loop — so the harness would argue with the captain about whether it is finished.

`paused` is the recorded form of *the captain has the wheel*. Both the guard and the watcher check it.

- If no mission id is given, pause the one currently executing. If several are, ask which.
- Leave any in-flight crewmate alone. Pausing stops **dispatch**, not work already running; say so, and offer `/crew send` to steer it or `--abandon` to stop it.
- `/resume` puts it back.
