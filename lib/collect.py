#!/usr/bin/env python3
"""Emit live Claude Code sessions on this host as JSON."""

from __future__ import annotations

import glob
import json
import os
import re
import socket
import subprocess
import sys
import time

CLAUDE = os.path.expanduser(os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude")
TAIL_CHARS = 2000
MAX_PID = 2 ** 31
SAFE_SID = re.compile(r"[A-Za-z0-9-]{1,64}")


def alive(pid: object) -> bool:
    if not isinstance(pid, int) or isinstance(pid, bool) or not 0 < pid < MAX_PID:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False
    return True


def tty_of(pid: int) -> str:
    try:
        out = subprocess.run(["ps", "-o", "tty=", "-p", str(pid)],
                             capture_output=True, text=True, timeout=5).stdout.strip()
    except Exception:
        return ""
    return "" if not out or "?" in out else out


def tmux_panes() -> dict[str, tuple[str, str]]:
    """tty -> (stable pane id, session name). Stable ids cannot be reused by a new pane."""
    try:
        out = subprocess.run(
            ["tmux", "list-panes", "-a", "-F", "#{pane_tty}\t#{pane_id}\t#{session_name}"],
            capture_output=True, text=True, timeout=5)
    except Exception:
        return {}
    if out.returncode != 0:
        return {}
    mapping = {}
    for line in out.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) == 3 and parts[0] and parts[1].startswith("%"):
            mapping[parts[0].replace("/dev/", "")] = (parts[1], parts[2])
    return mapping


def slug(cwd: str) -> str:
    return cwd.replace("/", "-")


def transcript_path(sid: str, cwd: str) -> str | None:
    direct = f"{CLAUDE}/projects/{slug(cwd)}/{sid}.jsonl"
    if os.path.isfile(direct):
        return direct
    hits = glob.glob(f"{CLAUDE}/projects/*/{sid}.jsonl")
    return hits[0] if hits else None


def last_assistant_text(path: str) -> str:
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as fh:
            fh.seek(max(0, size - 400_000))
            lines = fh.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return ""
    for line in reversed(lines):
        try:
            rec = json.loads(line)
        except Exception:
            continue
        if rec.get("type") != "assistant":
            continue
        content = (rec.get("message") or {}).get("content")
        if isinstance(content, list):
            text = "\n".join(c.get("text", "") for c in content if c.get("type") == "text")
        else:
            text = str(content or "")
        text = text.strip()
        if text:
            return text[-TAIL_CHARS:]
    return ""


def work_id(sid: str, cwd: str) -> str:
    ptr = f"{CLAUDE}/works/{slug(cwd)}/index/session/{sid}"
    try:
        with open(ptr) as fh:
            return fh.read().strip()
    except OSError:
        return ""


def since_ms(d: dict) -> float:
    for key in ("statusUpdatedAt", "updatedAt"):
        v = d.get(key)
        if isinstance(v, (int, float)) and not isinstance(v, bool):
            return float(v)
    return 0.0


def row(d: dict, host: str, panes: dict[str, tuple[str, str]]) -> dict | None:
    pid = d.get("pid")
    if not alive(pid):
        return None
    # Validated before it reaches a filesystem path: a crafted id could otherwise
    # traverse or glob into another project's transcript.
    sid = d.get("sessionId") or ""
    sid = sid if isinstance(sid, str) and SAFE_SID.fullmatch(sid) else ""
    cwd = d.get("cwd") if isinstance(d.get("cwd"), str) else ""
    try:
        tpath = transcript_path(sid, cwd) if sid and cwd else None
        mtime = os.path.getmtime(tpath) if tpath else 0.0
        tail = last_assistant_text(tpath) if tpath else ""
    except OSError:
        mtime, tail = 0.0, ""
    tty = tty_of(pid)
    pane, pane_session = panes.get(tty, ("", ""))
    name = d.get("name")
    return {
        "host": host,
        "sid": sid,
        "pid": pid,
        "proc_start": d.get("procStart") if isinstance(d.get("procStart"), str) else "",
        "tty": tty,
        "tmux": pane,
        "tmux_session": pane_session,
        "name": name if isinstance(name, str) and name else (sid[:8] or "unnamed"),
        "status": d.get("status") if isinstance(d.get("status"), str) else None,
        "status_since_ms": since_ms(d),
        "cwd": cwd,
        "work_id": work_id(sid, cwd) if sid and cwd else "",
        "transcript_mtime": mtime,
        "tail": tail,
    }


def collect() -> list[dict]:
    host = os.environ.get("CCSTATUS_HOST") or socket.gethostname()
    panes = tmux_panes()
    out = []
    for path in glob.glob(f"{CLAUDE}/sessions/*.json"):
        try:
            with open(path) as fh:
                d = json.load(fh)
        except Exception:
            continue
        if not isinstance(d, dict):
            continue
        try:
            entry = row(d, host, panes)
        except Exception:
            continue
        if entry:
            out.append(entry)
    out.sort(key=lambda r: r["status_since_ms"])
    return out


if __name__ == "__main__":
    json.dump({"collected_at": int(time.time()), "sessions": collect()}, sys.stdout)
    sys.stdout.write("\n")
