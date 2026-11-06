#!/usr/bin/env bash
# $1=host $2=name $3=session-id $4=tty $5=tmux-pane-id $6=tmux-session
# Focus the session if it is already open, otherwise resume it in a new tab.
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADAPTERS="$ROOT/adapters"
[ -f "$ROOT/config.env" ] && . "$ROOT/config.env"

HOST="${1:?host}"
NAME="${2:?session name}"
SID="${3:-}"
TTY="${4:-}"
PANE="${5:-}"
PANE_SESSION="${6:-}"

bad() { echo "refusing unsafe $1" >&2; exit 1; }
case "$NAME" in *[!A-Za-z0-9._-]*|"") bad "session name" ;; esac
case "$HOST" in *[!A-Za-z0-9._-]*|"") bad "host" ;; esac
case "$SID" in *[!A-Za-z0-9-]*) bad "session id" ;; esac
case "$TTY" in *[!A-Za-z0-9/]*) TTY="" ;; esac
case "$PANE" in %[0-9]*) : ;; *) PANE="" ;; esac
case "$PANE_SESSION" in *[!A-Za-z0-9._-]*) PANE_SESSION="" ;; esac

CLAUDE_BIN="${CCSTATUS_CLAUDE_BIN:-claude}"
FOCUS_CAPABLE="iterm2 apple-terminal wezterm"

launcher() { "$ROOT/bin/detect-terminal.sh" 2>/dev/null || echo fallback; }

# Try every adapter that can find a tab by tty, not just the detected one: a user may
# have iTerm installed while actually working in Terminal.app.
focus_tty() {
  local want="$1" a
  [ -n "$want" ] || return 1
  for a in $FOCUS_CAPABLE; do
    [ -x "$ADAPTERS/$a.sh" ] || continue
    "$ADAPTERS/$a.sh" probe >/dev/null 2>&1 || continue
    if "$ADAPTERS/$a.sh" focus-tty "$want" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

launch() {
  local cmd="$1" a
  a="$(launcher)"
  if [ -x "$ADAPTERS/$a.sh" ] && "$ADAPTERS/$a.sh" launch "$cmd"; then
    return 0
  fi
  "$ADAPTERS/fallback.sh" launch "$cmd"
}

resume_cmd() {
  if [ "$HOST" = "local" ]; then
    [ -n "$SID" ] || { echo "local resume needs a session id" >&2; exit 1; }
    printf '%s --resume %s' "$CLAUDE_BIN" "$SID"
    return
  fi
  local tmpl="${CCSTATUS_REMOTE_RESUME:-}"
  if [ -z "$tmpl" ]; then
    if [ -n "$PANE_SESSION" ]; then
      tmpl="ssh -t %h \"tmux attach -t %t 2>/dev/null || $CLAUDE_BIN --resume %s\""
    else
      tmpl="ssh -t %h \"$CLAUDE_BIN --resume %s\""
    fi
  fi
  tmpl="${tmpl//%h/$HOST}"
  tmpl="${tmpl//%n/$NAME}"
  tmpl="${tmpl//%s/$SID}"
  tmpl="${tmpl//%t/$PANE_SESSION}"
  printf '%s' "$tmpl"
}

# A session in a tmux pane can be reached from any terminal. The pane id is stable,
# so this also proves the pane is still the one that was collected.
focus_via_tmux() {
  [ "$HOST" = "local" ] || return 1
  [ -n "$PANE" ] || return 1
  command -v tmux >/dev/null 2>&1 || return 1
  tmux display-message -p -t "$PANE" '#{pane_id}' >/dev/null 2>&1 || return 1

  tmux select-pane -t "$PANE" 2>/dev/null || return 1
  tmux select-window -t "$PANE" 2>/dev/null || true

  local client
  client="$(tmux display-message -p -t "$PANE" '#{client_tty}' 2>/dev/null || true)"
  if [ -n "$client" ] && focus_tty "${client#/dev/}"; then
    return 0
  fi
  if [ -n "${TMUX:-}" ]; then
    tmux switch-client -t "$PANE" 2>/dev/null && return 0
  fi
  [ -n "$PANE_SESSION" ] || return 1
  launch "tmux attach -t $PANE_SESSION"
}

if focus_via_tmux; then
  exit 0
fi

if [ "$HOST" = "local" ] && focus_tty "$TTY"; then
  exit 0
fi

launch "$(resume_cmd)"
