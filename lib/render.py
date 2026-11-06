#!/usr/bin/env python3
"""Gather every host, classify, and print a SwiftBar menu (or plain text)."""

from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
HOSTS = [h.strip() for h in os.environ.get("CCSTATUS_HOSTS", "").split(",") if h.strip()]
REMOTE_DIR = os.environ.get("CCSTATUS_REMOTE_DIR", "~/.ccstatus")
FULL_BAR_HOURS = float(os.environ.get("CCSTATUS_FULL_BAR_HOURS", "4"))
BARS = 10
MONO = "font=Menlo size=12"
ACCENT = "#577cff"
OVERDUE = "#e8563f"
COLORS = {"NEEDS_YOU": ACCENT, "WORKING": ACCENT, "DONE": "#38a169", "SHELL": "#888888"}
ORDER = ["NEEDS_YOU", "DONE", "WORKING", "SHELL", "IDLE"]
STATE_OF_STATUS = {"busy": "WORKING", "shell": "SHELL"}

# fullmatch, not match: with `match` a trailing newline still passes `$`, and SwiftBar's
# menu format is line-oriented, so one newline forges a second clickable row.
SAFE_NAME = re.compile(r"[A-Za-z0-9._-]{1,64}")
SAFE_SID = re.compile(r"[A-Za-z0-9-]{1,64}")
SAFE_TTY = re.compile(r"[A-Za-z0-9/]{1,20}")
SAFE_TMUX = re.compile(r"%[0-9]{1,9}")
SAFE_TMUX_SESSION = re.compile(r"[A-Za-z0-9._-]{1,64}")
SAFE_HOST = re.compile(r"[A-Za-z0-9._-]{1,64}")
SAFE_REMOTE_DIR = re.compile(r"[A-Za-z0-9._~/-]{1,256}")

LAUNCHER = os.path.join(ROOT, "bin", "open-session.sh")
PLAIN = "--plain" in sys.argv


def safe(text: object, limit: int = 120) -> str:
    """Flatten anything that would forge extra SwiftBar rows or params."""
    cleaned = "".join(" " if ch in "\r\n\t|" or ord(ch) < 32 else ch for ch in str(text))
    return cleaned.strip()[:limit]


def ok(pattern: re.Pattern[str], value: object) -> str:
    """The value if it fully matches, else empty. Never a partial match."""
    text = value if isinstance(value, str) else ""
    return text if pattern.fullmatch(text) else ""


def run(cmd: list[str], stdin: str | None = None, timeout: int = 60,
        env: dict[str, str] | None = None) -> tuple[str, str]:
    try:
        p = subprocess.run(cmd, input=stdin, capture_output=True, text=True,
                           timeout=timeout, env=env)
    except subprocess.TimeoutExpired:
        return "", "timed out"
    except Exception as exc:
        return "", str(exc)
    if p.returncode != 0:
        tail = (p.stderr or "").strip().splitlines()
        return "", (tail[-1] if tail else f"exit {p.returncode}")
    return p.stdout, ""


def gather() -> tuple[list[dict], list[str]]:
    sessions: list[dict] = []
    errors: list[str] = []

    out, err = run([sys.executable, os.path.join(HERE, "collect.py")], timeout=30,
                   env=dict(os.environ, CCSTATUS_HOST="local"))
    if err:
        errors.append(f"local: {err}")
    else:
        try:
            sessions += json.loads(out)["sessions"]
        except Exception as exc:
            errors.append(f"local: bad JSON ({exc})")

    if HOSTS and not ok(SAFE_REMOTE_DIR, REMOTE_DIR):
        errors.append("CCSTATUS_REMOTE_DIR has unsafe characters; remote hosts skipped")
        return sessions, errors

    for host in HOSTS:
        # REMOTE_DIR is interpolated unquoted so the remote shell expands a leading ~.
        # SAFE_REMOTE_DIR above is what makes that safe.
        remote = f"CCSTATUS_HOST={shlex.quote(host)} python3 {REMOTE_DIR}/collect.py"
        out, err = run(
            ["ssh", "-o", "ConnectTimeout=8", "-o", "BatchMode=yes", host, remote],
            timeout=45,
        )
        if err or not out.strip():
            errors.append(f"{safe(host, 40)}: {err or 'no output'}")
            continue
        try:
            sessions += json.loads(out)["sessions"]
        except Exception as exc:
            errors.append(f"{safe(host, 40)}: bad JSON ({exc})")
    return sessions, errors


def bar(hours: float) -> str:
    filled = min(BARS, max(0, round(BARS * hours / FULL_BAR_HOURS))) if FULL_BAR_HOURS else 0
    return "█" * filled + "░" * (BARS - filled)


def human(hours: float) -> str:
    if hours < 1:
        return f"{int(hours * 60)}m"
    if hours < 48:
        return f"{hours:.0f}h"
    return f"{hours / 24:.0f}d"


def label_of(s: dict) -> str:
    where = "local" if s.get("host") == "local" else safe(s.get("host", ""), 8)
    name = safe(s.get("name", ""), 26)
    return f"{name:<26} {where:<8}{bar(s['stall_hours'])} {human(s['stall_hours']):>4}"


def click_params(s: dict) -> str:
    """Only emitted when every field is wholly safe; otherwise the row is not clickable."""
    host = "local" if s.get("host") == "local" else ok(SAFE_HOST, s.get("host"))
    name = ok(SAFE_NAME, s.get("name"))
    sid = ok(SAFE_SID, s.get("sid"))
    if not host or not name:
        return ""
    if host == "local" and not sid:
        return ""
    return (f" bash={shlex.quote(LAUNCHER)}"
            f" param0={shlex.quote(host)}"
            f" param1={shlex.quote(name)}"
            f" param2={shlex.quote(sid)}"
            f" param3={shlex.quote(ok(SAFE_TTY, s.get('tty')))}"
            f" param4={shlex.quote(ok(SAFE_TMUX, s.get('tmux')))}"
            f" param5={shlex.quote(ok(SAFE_TMUX_SESSION, s.get('tmux_session')))}"
            " terminal=false refresh=true")


def emit(s: dict, indent: str = "") -> None:
    color = COLORS.get(s["state"], "#999999")
    if s["state"] == "NEEDS_YOU" and s["stall_hours"] >= FULL_BAR_HOURS:
        color = OVERDUE
    print(f"{indent}{label_of(s)} | {MONO} color={color}{click_params(s)}")
    if s.get("ask"):
        print(f"{indent}  ↳ {safe(s['ask'], 60)} | {MONO} size=11 color=#999999")


def classify(sessions: list[dict]) -> tuple[list[dict], bool]:
    out, err = run([sys.executable, os.path.join(HERE, "classify.py")],
                   stdin=json.dumps({"sessions": sessions}), timeout=120)
    if err:
        return sessions, True
    try:
        data = json.loads(out)
    except Exception:
        return sessions, True
    return data["sessions"], bool(data.get("classifier_error"))


def backfill(sessions: list[dict]) -> None:
    now_ms = time.time() * 1000
    for s in sessions:
        since = s.get("status_since_ms")
        since = since if isinstance(since, (int, float)) and not isinstance(since, bool) else now_ms
        s.setdefault("stall_hours", round(max((now_ms - since) / 3_600_000, 0), 2))
        s.setdefault("state", STATE_OF_STATUS.get(s.get("status"), "IDLE"))


def group(sessions: list[dict]) -> dict[str, list[dict]]:
    groups: dict[str, list[dict]] = {}
    for s in sessions:
        groups.setdefault(s.get("state", "IDLE"), []).append(s)
    for rows in groups.values():
        rows.sort(key=lambda r: -r["stall_hours"])
    return groups


def print_plain(groups: dict[str, list[dict]], errors: list[str], degraded: bool) -> None:
    for state in ORDER + ["STALE"]:
        for s in groups.get(state) or []:
            ask = f"  <- {safe(s['ask'], 60)}" if s.get("ask") else ""
            print(f"{state:<10} {label_of(s)}{ask}")
    for e in errors:
        print(f"WARN  {safe(e, 70)}")
    if degraded:
        print("WARN  classifier unavailable - idle not split")


def print_menu(groups: dict[str, list[dict]], errors: list[str], degraded: bool) -> None:
    needs = groups.get("NEEDS_YOU", [])
    working = groups.get("WORKING", [])
    stalled_total = sum(s["stall_hours"] for s in needs)
    overdue = [s for s in needs if s["stall_hours"] >= FULL_BAR_HOURS]

    title = f"●{len(needs)}" if needs else "○"
    if working:
        title += f" ▶{len(working)}"
    if errors or degraded:
        title += " ⚠"
    print(f"{title} | color={OVERDUE if overdue else (ACCENT if needs or working else '#888888')}")
    print("---")
    print(f"{len(needs)} need you · {len(working)} working · {human(stalled_total)} stalled | size=12")

    if errors or degraded:
        print("---")
        for e in errors:
            print(f"⚠ {safe(e, 70)} | color=#e8a33f {MONO} size=11")
        if degraded:
            print(f"⚠ classifier unavailable — idle not split | color=#e8a33f {MONO} size=11")
    print("---")

    for state in ORDER:
        rows = groups.get(state) or []
        if not rows:
            continue
        print(f"{state.replace('_', ' ')} | color=#666666 size=11")
        for s in rows:
            emit(s)
        print("---")

    stale = groups.get("STALE") or []
    if stale:
        print(f"STALE ({len(stale)}) | bash=/usr/bin/true terminal=false")
        for s in stale:
            emit(s, indent="--")
        print("---")
    print("Refresh | refresh=true")


def main() -> int:
    sessions, errors = gather()
    sessions, degraded = classify(sessions)
    backfill(sessions)

    if not sessions and errors:
        if PLAIN:
            for e in errors:
                print(f"WARN  {safe(e, 70)}")
            return 0
        print("cc ⚠ | color=#e8a33f")
        print("---")
        for e in errors:
            print(f"unreachable — {safe(e, 70)} | color={OVERDUE} {MONO}")
        print("---")
        print("Refresh | refresh=true")
        return 0

    groups = group(sessions)
    if PLAIN:
        print_plain(groups, errors, degraded)
    else:
        print_menu(groups, errors, degraded)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
