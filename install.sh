#!/usr/bin/env bash
# Set up ccstatus on this machine. Safe to re-run.
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSUME_YES=0
[ "${1:-}" = "--yes" ] && ASSUME_YES=1

say() { printf '%s\n' "$*"; }
ok()  { printf '  ok    %s\n' "$*"; }
warn(){ printf '  warn  %s\n' "$*"; }
bad() { printf '  MISS  %s\n' "$*"; }

ask() {
  [ "$ASSUME_YES" = 1 ] && return 0
  [ -t 0 ] || return 1
  printf '%s [y/N] ' "$1"
  read -r a
  case "$a" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

say "ccstatus install"
say ""
say "Checking what you have:"

PY="$(command -v python3 || true)"
if [ -z "$PY" ] && [ -x /usr/bin/python3 ]; then PY=/usr/bin/python3; fi
if [ -z "$PY" ]; then
  bad "python3 not found. Install it (macOS: xcode-select --install; Debian: apt install python3)."
  exit 1
fi
if ! PYVER="$("$PY" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null)"; then
  bad "$PY exists but will not run. Fix your python3 install, then re-run."
  exit 1
fi
if ! "$PY" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] >= (3, 8) else 1)'; then
  bad "python3 is $PYVER; ccstatus needs 3.8 or newer."
  exit 1
fi
ok "python3 -> $PY ($PYVER)"

if [ ! -d "$HOME/.claude" ]; then
  bad "~/.claude does not exist. Install and run Claude Code once, then re-run this."
  exit 1
fi
ok "~/.claude present"

if [ -d "$HOME/.claude/sessions" ]; then
  ok "session registry present ($(ls "$HOME/.claude/sessions" 2>/dev/null | wc -l | tr -d ' ') entries)"
else
  warn "~/.claude/sessions missing - it appears when a session runs. Nothing to show until then."
fi

if command -v claude >/dev/null 2>&1; then
  ok "claude CLI on PATH"
else
  warn "claude CLI not on PATH. The NEEDS_YOU/DONE split needs it; everything else works."
  warn "Set CCSTATUS_CLAUDE_BIN in config.env, or CCSTATUS_CLASSIFY=0 to turn the split off."
fi

if command -v tmux >/dev/null 2>&1; then
  ok "tmux present - sessions inside tmux can be focused from any terminal"
else
  warn "tmux not found. Without it, focusing an existing tab only works on iTerm2/Terminal.app."
fi

chmod +x "$ROOT"/bin/*.sh "$ROOT"/adapters/*.sh "$ROOT"/remote/*.sh "$ROOT"/*.sh 2>/dev/null || true
ok "scripts executable"

if [ ! -f "$ROOT/config.env" ]; then
  cp "$ROOT/config.env.example" "$ROOT/config.env"
  ok "wrote config.env (from example)"
else
  ok "config.env already exists - left alone"
fi

ADAPTER="$("$ROOT/bin/detect-terminal.sh" 2>/dev/null || echo unknown)"
if [ "$ADAPTER" = "fallback" ] || [ "$ADAPTER" = "unknown" ]; then
  warn "no terminal adapter matched; clicks will copy the resume command to your clipboard."
  warn "Set CCSTATUS_TERMINAL in config.env if your terminal has an adapter."
else
  ok "terminal adapter -> $ADAPTER"
fi

say ""
if [ "$(uname)" != "Darwin" ]; then
  say "Not macOS, so there is no menu bar to install into. Use the plain renderer:"
  say "  $ROOT/bin/ccstatus.60s.sh --plain"
  say "Wire that into your status bar (waybar/polybar exec, or a tmux status-right)."
  exit 0
fi

if [ ! -d "/Applications/SwiftBar.app" ] && [ ! -d "$HOME/Applications/SwiftBar.app" ]; then
  bad "SwiftBar not installed - it is the menu-bar host."
  if command -v brew >/dev/null 2>&1; then
    if ask "Install it now with: brew install --cask swiftbar ?"; then
      brew install --cask swiftbar
    else
      say "Install it yourself, then re-run: brew install --cask swiftbar"
      exit 1
    fi
  else
    say "Homebrew is not installed either. Either install Homebrew (https://brew.sh) then"
    say "  brew install --cask swiftbar"
    say "or download SwiftBar from https://github.com/swiftbar/SwiftBar/releases"
    exit 1
  fi
fi
ok "SwiftBar installed"

PLUGIN_DIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
if [ -z "$PLUGIN_DIR" ]; then
  PLUGIN_DIR="$HOME/.ccstatus-plugins"
  mkdir -p "$PLUGIN_DIR"
  if ask "SwiftBar has no plugin folder set. Point it at $PLUGIN_DIR ?"; then
    defaults write com.ameba.SwiftBar PluginDirectory -string "$PLUGIN_DIR"
    ok "set SwiftBar plugin folder -> $PLUGIN_DIR"
  else
    say "Open SwiftBar, choose a plugin folder, then re-run this script."
    exit 1
  fi
else
  mkdir -p "$PLUGIN_DIR"
  ok "SwiftBar plugin folder -> $PLUGIN_DIR"
fi

LINK="$PLUGIN_DIR/ccstatus.60s.sh"
if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
  bad "$LINK exists and is not a symlink. Move it aside; refusing to overwrite it."
  exit 1
fi
ln -sfn "$ROOT/bin/ccstatus.60s.sh" "$LINK"
ok "linked plugin into $PLUGIN_DIR"

say ""
say "Done. Open SwiftBar (or its menu -> Refresh All) and you should see the indicator."
say "To add other machines:  ./remote/install-remote.sh <ssh-host>  then set CCSTATUS_HOSTS."
say "If something looks wrong: ./doctor.sh"
