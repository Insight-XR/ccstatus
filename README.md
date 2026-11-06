# ccstatus

A menu-bar view of which Claude Code sessions are waiting on **you**, across every machine you
work on, and a one-click way back into any of them.

Claude Code sessions pile up. Some are mid-task, some finished and reported a result, and some
stopped because they asked you a question nobody answered. Those last ones are invisible — the
session is idle, the terminal tab is buried, and the work quietly dies. ccstatus reads the session
registry Claude Code already maintains, works out which sessions are actually blocked on a human,
and shows them in one list with how long each has been waiting.

```
●3 ▶1 ⚠

3 need you · 1 working · 9h stalled

NEEDS YOU
  quote-margin-logic      local   ████████░░   4h
    ↳ approve the reviewer request
  planner-replay          dev-box ██████████  11h
    ↳ which model to pin
DONE
  id-model-tests          local   ███░░░░░░░   1h
WORKING
  nightly-eval            dev-box █░░░░░░░░░  20m
```

Click any row to jump to that session — it focuses the existing tab if the session is still open,
otherwise it opens a new one and resumes it.

---

## Requirements

Only two things are genuinely required:

| | Why | If missing |
|---|---|---|
| **Python 3.8+** | everything is stdlib Python | macOS ships it; `apt install python3` on Debian/Ubuntu |
| **Claude Code**, run at least once | creates `~/.claude` and the session registry | install it, start a session, then install this |

Optional, each buying you one thing:

| | Buys you | If missing |
|---|---|---|
| **SwiftBar** (macOS) | the menu bar itself | use `--plain` and wire it into any status bar |
| **`claude` on PATH** | the NEEDS\_YOU vs DONE split | set `CCSTATUS_CLASSIFY=0`; you still get WORKING/IDLE/STALE |
| **tmux** | focusing an existing tab in *any* terminal | focus works only on iTerm2 / Terminal.app |
| **ssh key auth to other hosts** | sessions on those machines | local sessions only |

There is **no** Homebrew requirement, no Node, no pip install, no virtualenv, and nothing to
compile. If you are on macOS and have used Claude Code, you already meet the requirements.

---

## Install

```bash
git clone https://github.com/Insight-XR/ccstatus.git
cd ccstatus
./install.sh
```

No git on the machine? Download the repo as a zip from its GitHub page ("Code" → "Download ZIP"),
unzip it anywhere, and run `./install.sh` from inside. Nothing depends on it being a git checkout.

The installer is safe to re-run, changes nothing it is not asked about, and prints what it found:

```
Checking what you have:
  ok    python3 -> /usr/bin/python3 (3.9.6)
  ok    ~/.claude present
  ok    session registry present (4 entries)
  ok    claude CLI on PATH
  ok    tmux present - sessions inside tmux can be focused from any terminal
  ok    config.env (from example)
  ok    terminal adapter -> iterm2
  ok    SwiftBar installed
  ok    linked plugin into /Users/you/.ccstatus-plugins
```

It will **ask before** installing SwiftBar or changing SwiftBar's plugin-folder setting, and it
never touches your shell config, your `~/.claude`, or anything on another machine.

Then open SwiftBar (menu → Refresh All). That is the whole local setup — there are no aliases to
add and nothing to put in `.zshrc`.

### Other machines

For each machine whose sessions you also want to see:

```bash
./remote/install-remote.sh my-dev-box
```

That copies one file (`lib/collect.py`) to `~/.ccstatus/` on that host and proves it runs there,
reporting how many live sessions it found. Then list the hosts in `config.env`:

```bash
export CCSTATUS_HOSTS=my-dev-box,another-box
```

Host names are plain ssh aliases, so whatever already works for `ssh my-dev-box` works here. It
must work **without a password prompt** (key auth), because the menu refreshes unattended.

### Not on macOS?

There is no menu bar to install into, but the renderer works anywhere:

```bash
./bin/ccstatus.60s.sh --plain
```

```
NEEDS_YOU  quote-margin-logic   local   ████████░░   4h  <- approve the reviewer request
WORKING    nightly-eval         dev-box █░░░░░░░░░  20m
```

Wire that into whatever you use — a waybar/polybar `exec` block, a tmux `status-right`, or just
an alias you run when you want to know what is waiting.

---

## Focusing: why tmux matters

Clicking a row tries three things in order, and stops at the first that works.

1. **tmux.** If the session lives in a tmux pane, ccstatus selects that pane by its *stable* pane
   id — so a pane that has since died or been renumbered cannot be confused for it. It then asks
   tmux which terminal tty the attached client is on and focuses *that* tab, so repeated clicks
   reuse your existing window instead of piling up new `attach`es. If nothing is attached and you
   are inside tmux it switches client; otherwise it opens one tab and attaches there.
2. **A native adapter.** For sessions *not* in tmux, ccstatus asks your terminal to find the tab by
   its tty. It tries every adapter that supports this, not just the detected one — so having iTerm
   installed while actually working in Terminal.app still finds the tab.
3. **The fallback.** If neither worked, the resume command goes to your clipboard and you get a
   desktop notification. On a machine with no clipboard tool it is printed instead. A click never
   does nothing at all, but on a bare Linux box "nothing visible happened" is possible — run
   `./doctor.sh` if that is you.

Running sessions inside tmux is what makes your choice of terminal stop mattering for step 1,
though a terminal that can focus by tty is still used to raise the right window. Without tmux, your
terminal decides what is possible:

| Adapter | Focus existing tab | Open new tab | Notes |
|---|---|---|---|
| `iterm2` | yes | yes | matches on tty |
| `apple-terminal` | yes | yes | matches on tty |
| `wezterm` | yes | yes | needs `wezterm cli` |
| `kitty` | no | yes | remote control exposes no pane tty |
| `ghostty` | no | yes | no scripting API for focus |
| `generic` | no | yes | Linux: `$CCSTATUS_TERM_CMD`, then gnome-terminal, konsole, alacritty, foot, xterm… |
| `fallback` | no | no | clipboard + notification |

Detection is automatic. Override it with `CCSTATUS_TERMINAL` in `config.env` if it guesses wrong.

**Your terminal is not listed?** An adapter is one small file. Copy `adapters/ghostty.sh`, which is
the minimal launch-only shape, and implement whichever verbs your terminal supports:

```
probe              exit 0 if this adapter is usable right now
focus-tty <tty>    focus the tab on that tty; exit non-zero if not found   (optional)
launch <command>   open a new tab/window running that command
```

Add its name to the list in `bin/detect-terminal.sh` and send a PR.

---

## Configuration

`install.sh` creates `config.env` from `config.env.example`. It is gitignored, so your hosts and
preferences stay yours. Every setting has a working default — an empty `config.env` is valid and
gives you local sessions with an auto-detected terminal.

| Variable | Default | What it does |
|---|---|---|
| `CCSTATUS_HOSTS` | *(empty)* | comma-separated ssh hosts to also poll |
| `CCSTATUS_REMOTE_DIR` | `~/.ccstatus` | where the collector lives on those hosts |
| `CCSTATUS_TERMINAL` | `auto` | force an adapter instead of detecting |
| `CCSTATUS_TERM_CMD` | *(unset)* | `generic` adapter: which terminal to launch |
| `CCSTATUS_CLASSIFY` | `1` | `0` disables the model call entirely |
| `CCSTATUS_MODEL` | `haiku` | model used for the NEEDS\_YOU / DONE split |
| `CCSTATUS_FULL_BAR_HOURS` | `4` | stall hours that fill the bar |
| `CCSTATUS_STALE_HOURS` | `48` | idle past this is STALE, and is not classified |
| `CCSTATUS_CLAUDE_BIN` | `claude` | absolute path, if `claude` is not on the GUI PATH |
| `CCSTATUS_REMOTE_RESUME` | ssh + tmux attach | template for resuming a remote session; `%h` host, `%n` name, `%s` session id |
| `CCSTATUS_STATE_DIR` | `~/.cache/ccstatus` | where the classifier cache lives |

---

## How it works

Three stdlib Python files, no state outside a cache:

- **`lib/collect.py`** runs once per host. It reads `~/.claude/sessions/*.json` — the registry
  Claude Code already writes, carrying `name`, `status` and `statusUpdatedAt` — drops any entry
  whose pid is gone, and attaches the tail of the last assistant message, the bound work contract
  id, the tty, and the tmux pane if there is one. It writes nothing.
- **`lib/classify.py`** splits idle sessions into NEEDS\_YOU and DONE with one batched
  `claude --print` call, keyed on `host:session:transcript_mtime:model`. The cache means the call
  only fires when a session has actually moved; sessions idle past `CCSTATUS_STALE_HOURS` are never
  classified at all. With `CCSTATUS_CLASSIFY=0` it does no model call and no network I/O.
- **`lib/render.py`** gathers every host, calls the classifier, and prints either a SwiftBar menu
  or plain text.

Bars are stall time normalised to `CCSTATUS_FULL_BAR_HOURS`. Nothing infers business importance —
a long bar means "waiting a long time", not "urgent".

### Cost

One `claude --print` call per refresh *that contains at least one newly-moved idle session*, on a
cheap model, batched across every session and every host. A steady-state refresh with nothing new
makes no model call. `CCSTATUS_CLASSIFY=0` makes it exactly zero.

### What leaves your machine

Be clear about this one, because it is on by default:

- **The classifier sends session names and the tail of the last assistant message** (up to 2000
  characters) to `claude --print`, i.e. to whatever model service your Claude Code is configured
  against. That is how NEEDS\_YOU is told from DONE. If your sessions discuss anything you would
  not send to that service, set `CCSTATUS_CLASSIFY=0` — you keep everything except that one split.
- **SSH polling** happens for each host in `CCSTATUS_HOSTS`, running exactly
  `python3 <CCSTATUS_REMOTE_DIR>/collect.py` and nothing else.

Beyond that it is read-only: it never writes to `~/.claude`, never resumes a session on its own,
and never contacts anything else. Clicking a row is the only action it takes, and that only focuses
a tab or starts a resume in a new one.

---

## Troubleshooting

Run `./doctor.sh` first — it prints the environment, the raw local collector output, per-host ssh
and collector status, and the rendered menu, which usually makes the problem obvious.

**Menu bar shows nothing / no icon.** SwiftBar is not running, or its plugin folder is not the one
the installer linked into. Check SwiftBar → Preferences → Plugin Folder against
`defaults read com.ameba.SwiftBar PluginDirectory`.

**`⚠ classifier unavailable — idle not split`.** `claude` is not on the PATH *that GUI apps get*,
which is often different from your shell's. Set `CCSTATUS_CLAUDE_BIN` to the absolute path from
`command -v claude`.

**A host shows `unreachable`.** The menu refreshes unattended, so ssh must need no interaction.
Test exactly what ccstatus does: `ssh -o BatchMode=yes <host> true`.

**A session appears that is long dead.** The registry entry outlived its process and its pid has
been reused by an unrelated process, so the liveness check still passes. It stays listed until that
unrelated process exits. Deleting the stale `~/.claude/sessions/<pid>.json` clears it immediately.

**Clicking does nothing.** You are on the `fallback` adapter — check `./bin/detect-terminal.sh`.
The resume command is on your clipboard; paste it to confirm, then either set `CCSTATUS_TERMINAL`
or run your sessions in tmux.

**A session is missing.** Headless sessions (`claude -p`) never register, by design, so they cannot
appear. Interactive ones appear within one refresh.

## Known limits

- Session names outside `[A-Za-z0-9._-]`, and ids outside `[A-Za-z0-9-]`, are shown but not
  clickable, deliberately: those values reach a launcher and a menu format that is line-oriented,
  so anything not wholly matching the allowlist gets no click action rather than a sanitised one.
- A reused pid can keep a dead session listed until the unrelated process exits.
- Priority is not modelled. Stall time is not importance.
- `kitty` and `ghostty` cannot focus an existing tab without tmux.
- Adapters other than `iterm2` are written from each terminal's documented interface but have not
  been exercised on a real machine. If one misbehaves, that is a bug worth filing, not your setup.
