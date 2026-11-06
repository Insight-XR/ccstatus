#!/usr/bin/env bash
set -eu
VERB="${1:?verb}"

case "$VERB" in
probe)
  [ "$(uname)" = "Darwin" ] || exit 1
  [ -d "/Applications/iTerm.app" ] || [ -d "$HOME/Applications/iTerm.app" ] || exit 1
  ;;
focus-tty)
  TTY="/dev/${2#/dev/}"
  /usr/bin/osascript - "$TTY" <<'OSA'
on run argv
  set wantTty to item 1 of argv
  tell application "iTerm"
    activate
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          try
            if (tty of s) is wantTty then
              select w
              select t
              select s
              return "focused"
            end if
          end try
        end repeat
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
  tell application "iTerm"
    activate
    if (count of windows) is 0 then
      create window with default profile
      tell current session of current window to write text cmd
    else
      tell current window
        create tab with default profile
        tell current session to write text cmd
      end tell
    end if
  end tell
end run
OSA
  ;;
*) exit 2 ;;
esac
