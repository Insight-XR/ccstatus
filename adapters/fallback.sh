#!/usr/bin/env bash
# Last resort: never fail silently. Put the command on the clipboard and say so.
set -eu
VERB="${1:?verb}"

copy() {
  if command -v pbcopy >/dev/null 2>&1; then pbcopy
  elif command -v wl-copy >/dev/null 2>&1; then wl-copy
  elif command -v xclip >/dev/null 2>&1; then xclip -selection clipboard
  else cat >/dev/null; return 1
  fi
}

notify() {
  if [ "$(uname)" = "Darwin" ]; then
    /usr/bin/osascript -e "display notification \"$1\" with title \"ccstatus\"" >/dev/null 2>&1 || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send "ccstatus" "$1" >/dev/null 2>&1 || true
  fi
}

case "$VERB" in
probe) exit 0 ;;
launch)
  CMD="${2:?command}"
  if printf '%s' "$CMD" | copy; then
    notify "Resume command copied to clipboard"
  else
    notify "No terminal adapter and no clipboard tool"
  fi
  printf '%s\n' "$CMD"
  ;;
*) exit 2 ;;
esac
