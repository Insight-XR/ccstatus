#!/usr/bin/env bash
# Launch-only: kitty's remote-control window list does not expose a pane tty,
# so tab focus goes through tmux instead (see README, Focusing).
set -eu
VERB="${1:?verb}"
command -v kitty >/dev/null 2>&1 || exit 1

case "$VERB" in
probe)
  kitty @ ls >/dev/null 2>&1
  ;;
launch)
  CMD="${2:?command}"
  kitty @ launch --type=tab -- "${SHELL:-/bin/sh}" -lc "$CMD; exec \${SHELL:-/bin/sh} -l"
  ;;
*) exit 2 ;;
esac
