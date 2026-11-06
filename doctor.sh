#!/usr/bin/env bash
# Prints what ccstatus sees and where it breaks. Read-only.
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$ROOT/config.env" ] && . "$ROOT/config.env"
PY="$(command -v python3 || echo /usr/bin/python3)"
REMOTE_DIR="${CCSTATUS_REMOTE_DIR:-~/.ccstatus}"
case "$REMOTE_DIR" in
  ""|-*|*[!A-Za-z0-9._~/-]*) echo "CCSTATUS_REMOTE_DIR is not a plain path: $REMOTE_DIR" >&2; exit 1 ;;
esac

line() { printf '\n== %s\n' "$*"; }

line "environment"
printf 'os          %s\n' "$(uname -srm)"
printf 'python3     %s (%s)\n' "$PY" "$("$PY" -c 'import sys;print(".".join(map(str,sys.version_info[:3])))')"
printf 'claude      %s\n' "$(command -v "${CCSTATUS_CLAUDE_BIN:-claude}" || echo 'NOT FOUND')"
printf 'tmux        %s\n' "$(command -v tmux || echo 'NOT FOUND')"
printf 'adapter     %s\n' "$("$ROOT/bin/detect-terminal.sh" 2>/dev/null || echo 'detect failed')"
printf 'hosts       %s\n' "${CCSTATUS_HOSTS:-(local only)}"
printf 'classify    %s\n' "${CCSTATUS_CLASSIFY:-1}"

line "local collector"
if OUT="$("$PY" "$ROOT/lib/collect.py" 2>&1)"; then
  printf '%s\n' "$OUT" | "$PY" -c '
import json, sys
rows = json.load(sys.stdin)["sessions"]
print("%d live session(s)" % len(rows))
for r in rows:
    print("  %-24s %-6s tty=%-8s tmux=%s" % (
        r.get("name") or "-",
        r.get("status") or "?",
        r.get("tty") or "-",
        r.get("tmux") or "-",
    ))
' || { echo "collector output was not valid JSON:"; printf '%s\n' "$OUT" | head -5; }
else
  echo "collector failed:"
  printf '%s\n' "$OUT" | head -10
fi

line "remote hosts"
if [ -z "${CCSTATUS_HOSTS:-}" ]; then
  echo "none configured"
else
  IFS=, read -r -a HOSTS <<< "$CCSTATUS_HOSTS"
  for h in "${HOSTS[@]}"; do
    [ -n "$h" ] || continue
    printf '%s: ' "$h"
    if ! ssh -o ConnectTimeout=8 -o BatchMode=yes "$h" true 2>/dev/null; then
      echo "ssh failed (key auth / host alias)"
    elif ! ssh -o BatchMode=yes "$h" "test -f $REMOTE_DIR/collect.py"; then
      echo "collector not installed - run ./remote/install-remote.sh $h"
    else
      echo "ok"
    fi
  done
fi

line "rendered menu"
"$ROOT/bin/ccstatus.60s.sh" --plain 2>&1 | head -30
