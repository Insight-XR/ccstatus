#!/usr/bin/env bash
set -eu
VERB="${1:?verb}"
command -v wezterm >/dev/null 2>&1 || exit 1

case "$VERB" in
probe)
  wezterm cli list --format json >/dev/null 2>&1
  ;;
focus-tty)
  TTY="/dev/${2#/dev/}"
  PANE="$(wezterm cli list --format json 2>/dev/null | python3 -c '
import json, sys
want = sys.argv[1]
for p in json.load(sys.stdin):
    if p.get("tty_name") == want:
        print(p["pane_id"])
        break
' "$TTY")"
  [ -n "$PANE" ] || exit 1
  wezterm cli activate-pane --pane-id "$PANE"
  ;;
launch)
  CMD="${2:?command}"
  wezterm cli spawn -- "${SHELL:-/bin/sh}" -lc "$CMD; exec \${SHELL:-/bin/sh} -l"
  ;;
*) exit 2 ;;
esac
