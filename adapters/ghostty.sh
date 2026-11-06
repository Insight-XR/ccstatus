#!/usr/bin/env bash
# Launch-only: Ghostty exposes no scripting API for focusing an existing tab,
# so tab focus goes through tmux instead (see README, Focusing).
set -eu
VERB="${1:?verb}"

case "$VERB" in
probe)
  [ "$(uname)" = "Darwin" ] || exit 1
  [ -d "/Applications/Ghostty.app" ] || [ -d "$HOME/Applications/Ghostty.app" ] || exit 1
  ;;
launch)
  CMD="${2:?command}"
  open -na Ghostty --args -e "${SHELL:-/bin/sh}" -lc "$CMD; exec \${SHELL:-/bin/sh} -l"
  ;;
*) exit 2 ;;
esac
