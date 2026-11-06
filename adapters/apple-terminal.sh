#!/usr/bin/env bash
set -eu
VERB="${1:?verb}"

case "$VERB" in
probe)
  [ "$(uname)" = "Darwin" ] || exit 1
  [ -d "/System/Applications/Utilities/Terminal.app" ] || [ -d "/Applications/Utilities/Terminal.app" ] || exit 1
  ;;
focus-tty)
  TTY="/dev/${2#/dev/}"
  /usr/bin/osascript - "$TTY" <<'OSA'
on run argv
  set wantTty to item 1 of argv
  tell application "Terminal"
    activate
    repeat with w in windows
      repeat with t in tabs of w
        try
          if (tty of t) is wantTty then
            set selected of t to true
            set index of w to 1
            return "focused"
          end if
        end try
      end repeat
    end repeat
  end tell
  error "not found"
end run
OSA
  ;;
launch)
  CMD="${2:?command}"
  /usr/bin/osascript - "$CMD" <<'OSA'
on run argv
  set cmd to item 1 of argv
  tell application "Terminal"
    activate
    do script cmd
  end tell
end run
OSA
  ;;
*) exit 2 ;;
esac
