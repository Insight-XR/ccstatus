#!/usr/bin/env bash
# Removes the SwiftBar link and the cache. Leaves the checkout and config.env.
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$ROOT/config.env" ] && . "$ROOT/config.env"

PLUGIN_DIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
if [ -n "$PLUGIN_DIR" ] && [ -L "$PLUGIN_DIR/ccstatus.60s.sh" ]; then
  rm -f "$PLUGIN_DIR/ccstatus.60s.sh"
  echo "removed $PLUGIN_DIR/ccstatus.60s.sh"
else
  echo "no SwiftBar plugin link found"
fi

# Only the one file we create. CCSTATUS_STATE_DIR may point at a shared directory,
# so this never removes the directory's other contents.
STATE_DIR="${CCSTATUS_STATE_DIR:-$HOME/.cache/ccstatus}"
if [ -f "$STATE_DIR/cache.json" ]; then
  rm -f "$STATE_DIR/cache.json" "$STATE_DIR/cache.json.tmp"
  echo "removed $STATE_DIR/cache.json"
  rmdir "$STATE_DIR" 2>/dev/null && echo "removed empty $STATE_DIR" || true
else
  echo "no classifier cache found"
fi

echo "Left in place: this checkout, config.env, SwiftBar itself, and anything on remote hosts."
echo "Remote collectors: ssh <host> 'rm -rf ${CCSTATUS_REMOTE_DIR:-~/.ccstatus}'"
