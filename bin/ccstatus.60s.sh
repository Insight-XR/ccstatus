#!/usr/bin/env bash
# <bitbar.title>Claude Session Status</bitbar.title>
# <bitbar.version>1.0</bitbar.version>
# <bitbar.author>ccstatus</bitbar.author>
# <bitbar.desc>Which Claude Code sessions are waiting on you, and for how long.</bitbar.desc>
# <bitbar.dependencies>python3</bitbar.dependencies>
set -eu

export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/bin:$PATH"

PY="$(command -v python3 || echo /usr/bin/python3)"
ROOT="$("$PY" -c 'import os,sys; print(os.path.dirname(os.path.dirname(os.path.realpath(sys.argv[1]))))' "${BASH_SOURCE[0]}")"

[ -f "$ROOT/config.env" ] && . "$ROOT/config.env"

exec "$PY" "$ROOT/lib/render.py" "$@"
