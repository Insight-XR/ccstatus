#!/usr/bin/env bash
# Print the adapter name to use. Honours CCSTATUS_TERMINAL when it is not "auto".
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADAPTERS="$ROOT/adapters"
[ -f "$ROOT/config.env" ] && . "$ROOT/config.env"

if [ -n "${CCSTATUS_TERMINAL:-}" ] && [ "$CCSTATUS_TERMINAL" != "auto" ]; then
  printf '%s\n' "$CCSTATUS_TERMINAL"
  exit 0
fi

for a in iterm2 wezterm kitty ghostty apple-terminal generic; do
  if [ -x "$ADAPTERS/$a.sh" ] && "$ADAPTERS/$a.sh" probe >/dev/null 2>&1; then
    printf '%s\n' "$a"
    exit 0
  fi
done

printf 'fallback\n'
