#!/usr/bin/env bash
# Linux / unknown-terminal launcher. Honours $CCSTATUS_TERM_CMD first, else tries
# the usual suspects. Launch-only; focus goes through tmux.
set -eu
VERB="${1:?verb}"

candidates() {
  [ -n "${CCSTATUS_TERM_CMD:-}" ] && echo "$CCSTATUS_TERM_CMD"
  echo x-terminal-emulator
  echo gnome-terminal
  echo konsole
  echo xfce4-terminal
  echo alacritty
  echo foot
  echo xterm
}

first_available() {
  candidates | while read -r c; do
    [ -n "$c" ] || continue
    if command -v "${c%% *}" >/dev/null 2>&1; then
      echo "$c"
      return
    fi
  done
}

case "$VERB" in
probe)
  [ -n "$(first_available)" ] || exit 1
  ;;
launch)
  CMD="${2:?command}"
  TERM_CMD="$(first_available)"
  [ -n "$TERM_CMD" ] || exit 1
  # shellcheck disable=SC2086
  exec $TERM_CMD -e "${SHELL:-/bin/sh}" -lc "$CMD; exec \${SHELL:-/bin/sh} -l"
  ;;
*) exit 2 ;;
esac
