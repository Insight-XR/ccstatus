#!/usr/bin/env bash
# ./remote/install-remote.sh <ssh-host> [more hosts...]
# Copies the collector to each host and proves it runs there.
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$ROOT/config.env" ] && . "$ROOT/config.env"
REMOTE_DIR="${CCSTATUS_REMOTE_DIR:-~/.ccstatus}"
# Interpolated unquoted so the remote shell expands a leading ~; this is what makes that safe.
case "$REMOTE_DIR" in
  ""|-*|*[!A-Za-z0-9._~/-]*) echo "CCSTATUS_REMOTE_DIR is not a plain path: $REMOTE_DIR" >&2; exit 1 ;;
esac

[ "$#" -ge 1 ] || { echo "usage: $0 <ssh-host> [more hosts...]" >&2; exit 2; }

for HOST in "$@"; do
  printf '%s: ' "$HOST"

  if ! ssh -o ConnectTimeout=8 -o BatchMode=yes "$HOST" true 2>/dev/null; then
    echo "cannot ssh non-interactively (set up key auth first)"
    continue
  fi

  if ! ssh -o BatchMode=yes "$HOST" 'command -v python3 >/dev/null 2>&1'; then
    echo "no python3 on that host"
    continue
  fi

  ssh -o BatchMode=yes "$HOST" "mkdir -p $REMOTE_DIR"
  scp -q "$ROOT/lib/collect.py" "$HOST:$REMOTE_DIR/collect.py"

  COUNT="$(ssh -o BatchMode=yes "$HOST" \
    "CCSTATUS_HOST=$HOST python3 $REMOTE_DIR/collect.py" 2>/dev/null \
    | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["sessions"]))' 2>/dev/null || true)"

  if [ -z "$COUNT" ]; then
    echo "installed, but the collector produced no valid JSON - run it by hand there"
    continue
  fi
  echo "ok ($COUNT live session(s))"
done

echo
echo "Now add them to config.env, e.g.:  export CCSTATUS_HOSTS=$(printf '%s,' "$@" | sed 's/,$//')"
