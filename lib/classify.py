#!/usr/bin/env python3
"""Split idle sessions into NEEDS_YOU / DONE with a cached, stateless model call."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time

STATE_DIR = os.path.expanduser(os.environ.get("CCSTATUS_STATE_DIR") or "~/.cache/ccstatus")
CACHE = os.path.join(STATE_DIR, "cache.json")
MODEL = os.environ.get("CCSTATUS_MODEL", "haiku")
STALE_HOURS = float(os.environ.get("CCSTATUS_STALE_HOURS", "48"))
CALL_TIMEOUT = int(os.environ.get("CCSTATUS_TIMEOUT", "90"))
ENABLED = os.environ.get("CCSTATUS_CLASSIFY", "1") != "0"
CLAUDE_BIN = os.environ.get("CCSTATUS_CLAUDE_BIN") or "claude"

PROMPT = """For each numbered session below, decide what its last assistant message means.

NEEDS_YOU - it asked the user something, offered a choice, or requested approval, and cannot
            proceed until the user answers.
DONE      - it finished, reported a result, or made a statement needing no reply.

Also give `ask`: what is owed from the user, under 60 characters, plain words. Empty for DONE.

Reply with ONLY a JSON array, one object per session, no prose:
[{"i": 0, "state": "NEEDS_YOU", "ask": "which model to pin"}]

"""


def cache_key(s: dict) -> str:
    return f"{s.get('host')}:{s.get('sid')}:{s.get('transcript_mtime')}:{MODEL}"


def load_cache() -> dict:
    try:
        with open(CACHE) as fh:
            return json.load(fh)
    except Exception:
        return {}


def save_cache(cache: dict) -> None:
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        trimmed = dict(sorted(cache.items(), key=lambda kv: kv[1].get("at", 0), reverse=True)[:500])
        tmp = CACHE + ".tmp"
        with open(tmp, "w") as fh:
            json.dump(trimmed, fh)
        os.replace(tmp, CACHE)
    except OSError:
        pass


def parse_verdicts(raw: str, count: int) -> dict[int, dict]:
    start, end = raw.find("["), raw.rfind("]")
    if start < 0 or end < 0:
        return {}
    try:
        parsed = json.loads(raw[start:end + 1])
    except Exception:
        return {}
    if not isinstance(parsed, list):
        return {}
    out: dict[int, dict] = {}
    for rec in parsed:
        if not isinstance(rec, dict):
            continue
        i = rec.get("i")
        if not isinstance(i, int) or isinstance(i, bool) or not 0 <= i < count or i in out:
            continue
        if rec.get("state") not in ("NEEDS_YOU", "DONE"):
            continue
        ask = rec.get("ask")
        out[i] = {"state": rec["state"], "ask": ask if isinstance(ask, str) else ""}
    return out


def ask_model(items: list[dict]) -> dict[int, dict]:
    if not shutil.which(CLAUDE_BIN):
        return {}
    blocks = [PROMPT]
    for i, s in enumerate(items):
        blocks.append(f"=== session {i} ({s['name']}) ===\n{s['tail']}\n")
    try:
        proc = subprocess.run(
            [CLAUDE_BIN, "--print", "--model", MODEL],
            input="\n".join(blocks),
            capture_output=True,
            text=True,
            timeout=CALL_TIMEOUT,
        )
    except Exception:
        return {}
    return parse_verdicts(proc.stdout.strip(), len(items))


def presort(sessions: list[dict], now_ms: float, cache: dict) -> list[dict]:
    pending: list[dict] = []
    for s in sessions:
        age_h = (now_ms - (s.get("status_since_ms") or now_ms)) / 3_600_000
        s["stall_hours"] = round(max(age_h, 0), 2)
        status = s.get("status")
        if status == "busy":
            s["state"] = "WORKING"
        elif status == "shell":
            s["state"] = "SHELL"
        elif age_h >= STALE_HOURS:
            s["state"] = "STALE"
        elif not s.get("tail") or not ENABLED:
            s["state"] = "IDLE"
        else:
            hit = cache.get(cache_key(s))
            if hit:
                s["state"], s["ask"] = hit["state"], hit.get("ask", "")
            else:
                s["state"] = "IDLE"
                pending.append(s)
    return pending


def main() -> int:
    data = json.load(sys.stdin)
    sessions = data.get("sessions", [])
    cache = load_cache()
    pending = presort(sessions, time.time() * 1000, cache)

    if pending:
        verdicts = ask_model(pending)
        if not verdicts:
            data["classifier_error"] = True
        for idx, verdict in verdicts.items():
            s = pending[idx]
            s["state"], s["ask"] = verdict["state"], verdict["ask"]
            cache[cache_key(s)] = {**verdict, "at": int(time.time())}
        save_cache(cache)

    for s in sessions:
        s.pop("tail", None)
    json.dump(data, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
