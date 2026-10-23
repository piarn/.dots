# Session Fallbacks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When quickshell or sway breaks, the session falls back to something usable: the last good quickshell config, swaylock, sway's stock config, or a TTY rescue command.

**Architecture:** Four small shell pieces, each owning one failure: `dots-lock` (lock with a swaylock fallback), `qs-watchdog` (last-good quickshell config), `sway-session` (safe-mode retry, moved into the repo), `dots-rescue` (TTY/ssh recovery), plus a `sway -C` gate in `dots-reload`. Every script takes environment overrides for the paths/commands it touches so tests run against stubs, never the live session.

**Tech Stack:** POSIX sh / bash, quickshell IPC, swaymsg, swaylock, GNU stow; tests are plain bash scripts under `tests/`.

**Spec:** `docs/superpowers/specs/2026-09-30-session-fallbacks-design.md`

## Global Constraints

- Branch: `experiment` in `~/.dots`. Commit after each task; messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- `qs ipc call` exits 0 even when the target doesn't exist ("Target not found."); non-zero only when no instance runs. Never use its exit code as proof of anything.
- `sway -C` must be run as `sway --unsupported-gpu -C` (always fails without it on the NVIDIA machine).
- Tests must never kill, lock, reload or message the live session: stub `pkill`, `swaymsg`, `swaylock`, `logger`, `qs` via `PATH`/env overrides.
- quickshell launch line (same as sway's exec_always): `env QML2_IMPORT_PATH=$HOME/.rice $HOME/.local/bin/quickshell -n`
- Last-good snapshot path: `~/.local/state/dots/quickshell-good`
- Scripts stay shellcheck-clean at `--severity=warning` (CI's setting).
- New files under a stow package only reach `$HOME` after `stow -v --no-folding -t "$HOME" <pkg>`; restart quickshell only after its new files are linked.

## Review Focus

1. swaylock already running (a previous fallback) when something locks again → dots-lock must not start a second swaylock. (Task 1 test)
2. quickshell slow to come up after a watchdog restart while the session should be locked → no premature swaylock; the watchdog waits 10s. (Task 1 test: slow stub with a long wait)
3. After a sway reload, a fresh real-config instance starts next to a running fallback → if it loads, the fallback is retired; if it fails, no second fallback starts. (Task 2 tests)
4. sway exiting non-zero after a long, normal session (logout, crash later on) → no safe-mode retry. (Task 3 test)
5. dots-rescue over ssh with stale sway IPC sockets from earlier sessions → it picks the live sway. (Task 5 test)

---

### Task 1: Test helpers, dots-lock, isLocked IPC, lock callers

**Files:**
- Create: `tests/lib.sh`, `tests/run.sh`, `tests/test-dots-lock.sh`
- Create: `scripts/.local/bin/dots-lock`
- Modify: `quickshell/.config/quickshell/popups/LockScreen.qml` (IpcHandler at the end)
- Modify: `sway/.config/sway/config:126` (`$mod+Escape`)
- Modify: `sway/.config/systemd/user/swayidle.service` (ExecStart)
- Modify: `quickshell/.config/quickshell/popups/commandcenter/RunSection.qml` (the `lock` session action)
- Modify: `.bootstrap/packages.txt` (add swaylock)

**Interfaces:**
- Produces: `dots-lock` (no args). Env overrides: `DOTS_LOCK_QS` (qs command, default `$HOME/.local/bin/qs`), `DOTS_LOCK_WAIT` (tenths of a second to wait for quickshell's lock, default 20), `DOTS_LOCK_FLAG` (default `$XDG_RUNTIME_DIR/quickshell-locked`). Exit 0 once locked by either locker.
- Produces: quickshell IPC `lock.isLocked(): bool` printing `true`/`false`.
- Produces: `tests/lib.sh` helpers: `stub NAME BODY`, `check NAME CMD...`, `finish`, vars `TMP`, `REPO`, `BIN`, `CALLS`.

- [ ] **Step 1: Write the test helpers**

`tests/lib.sh`:
```bash
#!/usr/bin/env bash
# Sourced by tests/test-*.sh. Stubs go first on PATH so a test never
# reaches the live session's quickshell, sway or lockers.
set -u
fails=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BIN=$REPO/scripts/.local/bin
CALLS=$TMP/calls
: >"$CALLS"
mkdir -p "$TMP/stubs"
export PATH="$TMP/stubs:$PATH"

# stub NAME BODY: a command NAME on PATH running BODY (sh), which can
# append to $CALLS to record that it ran.
stub() {
    printf '#!/bin/sh\nCALLS=%s\n%s\n' "$CALLS" "$2" >"$TMP/stubs/$1"
    chmod +x "$TMP/stubs/$1"
}

check() {
    local name=$1
    shift
    if "$@"; then printf '  ok    %s\n' "$name"; else printf '  FAIL  %s\n' "$name"; fails=$((fails + 1)); fi
}

called() { grep -qF -- "$1" "$CALLS"; }
not_called() { ! grep -qF -- "$1" "$CALLS"; }

finish() { [ "$fails" -eq 0 ]; }
```

`tests/run.sh`:
```bash
#!/usr/bin/env bash
# Runs every tests/test-*.sh; exits non-zero if any failed.
cd "$(dirname "$0")" || exit 1
status=0
for t in test-*.sh; do
    echo "$t"
    bash "$t" || status=1
done
exit "$status"
```

- [ ] **Step 2: Write the failing dots-lock test**

`tests/test-dots-lock.sh`:
```bash
#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

# qs stub: QS_MODE works | slow | broken | none
stub qs '
echo "qs $*" >>"$CALLS"
case "$QS_MODE:$4" in
    works:lock) touch "$CALLS.locked" ;;
    slow:lock) (sleep 0.5; touch "$CALLS.locked") & ;;
    works:isLocked|slow:isLocked) [ -e "$CALLS.locked" ] && echo true || echo false ;;
    broken:*) echo "Target not found." ;;
    none:*) exit 255 ;;
esac'
stub swaylock 'echo "swaylock $*" >>"$CALLS"'
stub logger ':'
stub pgrep 'exit "${PGREP_RC:-1}"'

export DOTS_LOCK_QS=$TMP/stubs/qs DOTS_LOCK_FLAG=$TMP/flag DOTS_LOCK_WAIT=3

reset() { : >"$CALLS"; rm -f "$CALLS.locked"; echo 1 >"$TMP/flag"; }

reset; QS_MODE=works "$BIN/dots-lock"
check "quickshell locks: asks it to lock" called "qs ipc call lock lock"
check "quickshell locks: no swaylock" not_called "swaylock"

reset; QS_MODE=broken "$BIN/dots-lock"
check "config didn't load (target missing): swaylock" called "swaylock -f -c"

reset; QS_MODE=none "$BIN/dots-lock"
check "quickshell not running: swaylock" called "swaylock -f -c"

reset; QS_MODE=broken "$BIN/dots-lock"; sleep 0.3
check "swaylock fallback: stale lock flag reset once swaylock is gone" [ "$(cat "$TMP/flag")" = 0 ]

reset; PGREP_RC=0 QS_MODE=broken "$BIN/dots-lock"
check "swaylock already running: nothing started" not_called "swaylock"
check "swaylock already running: quickshell not asked" not_called "call lock lock"

reset; touch "$CALLS.locked"; QS_MODE=works "$BIN/dots-lock"
check "already locked by quickshell: not asked again" not_called "call lock lock"

reset; QS_MODE=slow DOTS_LOCK_WAIT=20 "$BIN/dots-lock"
check "slow quickshell within the wait: no swaylock" not_called "swaylock"

reset; QS_MODE=slow DOTS_LOCK_WAIT=1 "$BIN/dots-lock"
check "slow quickshell past the wait: swaylock" called "swaylock -f -c"

finish
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bash tests/test-dots-lock.sh`
Expected: FAIL lines (dots-lock doesn't exist: "No such file or directory").

- [ ] **Step 4: Write dots-lock**

`scripts/.local/bin/dots-lock`:
```sh
#!/bin/sh
# Locks the session: quickshell's lock screen, or swaylock when that
# doesn't come up (quickshell not running, or running a config that failed
# to load). The only thing that locks — $mod+Escape, swayidle, the command
# center's :lock and qs-watchdog's re-lock all run this.
#
# `qs ipc call` exits 0 even when the lock target doesn't exist, so the
# lock is confirmed with isLocked instead of trusting that. swaylock -f
# forks once the screen is locked, so `swayidle -w` before-sleep still
# waits for the lock.
#
# DOTS_LOCK_QS, DOTS_LOCK_WAIT (tenths of a second), DOTS_LOCK_FLAG: for tests.
qs="${DOTS_LOCK_QS:-$HOME/.local/bin/qs}"
wait="${DOTS_LOCK_WAIT:-20}"
flag="${DOTS_LOCK_FLAG:-${XDG_RUNTIME_DIR:-/tmp}/quickshell-locked}"

qs_locked() { [ "$("$qs" ipc call lock isLocked 2>/dev/null)" = true ]; }
swaylock_up() { pgrep -u "$(id -u)" -x swaylock >/dev/null; }

swaylock_up && exit 0
qs_locked && exit 0

"$qs" ipc call lock lock >/dev/null 2>&1
i=0
while [ "$i" -lt "$wait" ]; do
    qs_locked && exit 0
    sleep 0.1
    i=$((i + 1))
done

logger -t dots-lock "quickshell's lock screen didn't come up; locking with swaylock"
color=$(sed -n 's/^set -g @color-black *"#\([0-9a-fA-F]\{6\}\)".*/\1/p' "$HOME/.rice/tmux/theme.conf" 2>/dev/null)
swaylock -f -c "${color:-000000}" || exit 1
# Once swaylock exits the session is unlocked, so a quickshell restarting
# later mustn't lock again from a flag its last instance left at 1.
(
    while swaylock_up; do sleep 1; done
    echo 0 >"$flag"
) >/dev/null 2>&1 &
exit 0
```
Then: `chmod +x scripts/.local/bin/dots-lock tests/run.sh tests/test-dots-lock.sh`

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tests/test-dots-lock.sh`
Expected: every line `ok`, exit 0.

- [ ] **Step 6: Add isLocked to the lock IPC**

In `quickshell/.config/quickshell/popups/LockScreen.qml`, replace the IpcHandler at the end with:
```qml
    IpcHandler {
        target: "lock"
        function lock(): void { sessionLock.locked = true }
        // dots-lock's proof the lock engaged (`qs ipc call` itself exits 0
        // even when this target doesn't exist)
        function isLocked(): bool { return sessionLock.locked }
    }
```

- [ ] **Step 7: Point every lock caller at dots-lock**

- `sway/.config/sway/config` line 126: `bindsym $mod+Escape exec $qs ipc call lock lock` → `bindsym $mod+Escape exec ~/.local/bin/dots-lock`
- `sway/.config/systemd/user/swayidle.service` ExecStart → `ExecStart=swayidle -w timeout 600 '%h/.local/bin/dots-lock' before-sleep '%h/.local/bin/dots-lock'`
- `RunSection.qml`, the `lock` session action: `cmd: ["qs", "ipc", "call", "lock", "lock"] },` → `cmd: [Quickshell.env("HOME") + "/.local/bin/dots-lock"] },`
- `.bootstrap/packages.txt`, in the desktop stack block after `swayidle`: add a line `swaylock` (same name on dnf/apt/pacman).

Check nothing else locks directly: `grep -rn 'ipc call lock lock' --exclude-dir=.git . | grep -v -e dots-lock -e docs/ -e tests/`
Expected: only `scripts/.local/bin/qs-watchdog` (changed in Task 2).

- [ ] **Step 8: Verify on the live session (read-only)**

```bash
stow -v --no-folding -t "$HOME" scripts sway quickshell
systemctl --user daemon-reload && systemctl --user restart swayidle.service
~/.local/bin/dots-reload quickshell sway
sleep 5; qs ipc call lock isLocked
```
Expected: `false`. (Locking for real is the user's check in Task 6.)

- [ ] **Step 9: Commit**

```bash
git add tests scripts/.local/bin/dots-lock quickshell/.config/quickshell/popups/LockScreen.qml sway/.config/sway/config sway/.config/systemd/user/swayidle.service quickshell/.config/quickshell/popups/commandcenter/RunSection.qml .bootstrap/packages.txt
git commit -m "dots-lock: lock via quickshell, fall back to swaylock

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: qs-watchdog runs the last-good config when a config fails to load

**Files:**
- Modify: `scripts/.local/bin/qs-watchdog` (full rewrite below)
- Create: `tests/test-qs-watchdog.sh`

**Interfaces:**
- Consumes: `dots-lock` with `DOTS_LOCK_WAIT` (Task 1).
- Produces: sourcing `qs-watchdog` with `QS_WATCHDOG_LIB=1` defines, without running the loop: `config_state PID` → prints `loaded|failed|pending`; `is_fallback PID` → status; `snapshot` → copies `$live` to `$good`; `check_configs` → one pass; `list_instances` (overridable). Env overrides: `QS_RUN` (runtime dir), `QS_GOOD`, `QS_LIVE`.
- Produces for Task 5: snapshot at `~/.local/state/dots/quickshell-good` containing `shell.qml`.

- [ ] **Step 1: Write the failing test**

`tests/test-qs-watchdog.sh`:
```bash
#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

stub swaymsg 'echo "swaymsg $*" >>"$CALLS"'
stub logger ':'
export QS_RUN=$TMP/run QS_GOOD=$TMP/good QS_LIVE=$TMP/live
QS_WATCHDOG_LIB=1 . "$BIN/qs-watchdog"

# a live config whose files are symlinks, like stow's
mkdir -p "$TMP/src" "$QS_LIVE/popups"
echo "shell v1" >"$TMP/src/shell.qml"
ln -s "$TMP/src/shell.qml" "$QS_LIVE/shell.qml"
echo "popup" >"$QS_LIVE/popups/P.qml"

# fake instances: real processes (so kill works), with logs like quickshell's
# output redirected, or $(spawn) would wait for the background sleep
spawn() { sh -c 'sleep 30' "$@" >/dev/null 2>&1 & echo $!; }
log() { mkdir -p "$QS_RUN/quickshell/by-pid/$1"; echo "$2" >"$QS_RUN/quickshell/by-pid/$1/log.log"; }
alive() { kill -0 "$1" 2>/dev/null; }
dead() { ! alive "$1"; }

p=$(spawn x); log "$p" "INFO: Configuration Loaded"
check "config_state loaded" [ "$(config_state "$p")" = loaded ]
log "$p" "ERROR: Failed to load configuration"
check "config_state failed" [ "$(config_state "$p")" = failed ]
log "$p" "INFO: Launching config"
check "config_state pending" [ "$(config_state "$p")" = pending ]
f=$(spawn x -p "$QS_GOOD")
check "is_fallback: snapshot instance" is_fallback "$f"
check "is_fallback: live instance" ! is_fallback "$p"
kill "$p" "$f"

snapshot
check "snapshot copies file contents" [ "$(cat "$QS_GOOD/shell.qml")" = "shell v1" ]
check "snapshot resolves symlinks" [ ! -L "$QS_GOOD/shell.qml" ]
check "snapshot copies subdirectories" [ -f "$QS_GOOD/popups/P.qml" ]
echo "shell v2" >"$TMP/src/shell.qml"; snapshot
check "snapshot refreshes on change" [ "$(cat "$QS_GOOD/shell.qml")" = "shell v2" ]

# failed config, snapshot present: killed, snapshot started, nag shown
: >"$CALLS"; checked=""
p=$(spawn x); log "$p" "ERROR: Failed to load configuration"
list_instances() { echo "$p"; }
check_configs; sleep 0.2
check "failed: instance killed" dead "$p"
check "failed: snapshot started" called "-p $QS_GOOD"
check "failed: user told" called "swaynag"

# failed while a fallback already runs: no second fallback
: >"$CALLS"; checked=""
f=$(spawn x -p "$QS_GOOD"); p=$(spawn x); log "$p" "ERROR: Failed to load configuration"
list_instances() { echo "$f"; echo "$p"; }
check_configs; sleep 0.2
check "failed with fallback up: not started twice" not_called "-p $QS_GOOD"
check "failed with fallback up: fallback kept" alive "$f"

# live config loads again: fallback retired, snapshot refreshed
: >"$CALLS"; checked=""
echo "shell v3" >"$TMP/src/shell.qml"
p=$(spawn x); log "$p" "INFO: Configuration Loaded"
list_instances() { echo "$f"; echo "$p"; }
check_configs; sleep 0.2
check "loaded with fallback up: fallback killed" dead "$f"
check "loaded: live instance kept" alive "$p"
check "loaded: snapshot refreshed" [ "$(cat "$QS_GOOD/shell.qml")" = "shell v3" ]
kill "$p"

# failed with no snapshot yet: told so, nothing started
: >"$CALLS"; checked=""; rm -rf "$QS_GOOD"
p=$(spawn x); log "$p" "ERROR: Failed to load configuration"
list_instances() { echo "$p"; }
check_configs
check "no snapshot: nothing started" not_called "-p $QS_GOOD"
check "no snapshot: user told about dots-rescue" called "dots-rescue"

finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-qs-watchdog.sh`
Expected: FAIL (`config_state: command not found` etc.; the current script also grabs the real lock and loops, so run it with `timeout 10`).

- [ ] **Step 3: Rewrite qs-watchdog**

`scripts/.local/bin/qs-watchdog`:
```sh
#!/bin/sh
# Force-restarts quickshell when its main thread stops responding, and
# falls back to the last config that loaded when a new one doesn't.
#
# Hangs: every bar popup is a fullscreen layer surface with exclusive
# keyboard focus, so a quickshell that hangs with one open swallows all
# input until it dies — plain `qs kill`/SIGTERM don't help, since both are
# handled on the same frozen event loop. quickshell rewrites
# $XDG_RUNTIME_DIR/quickshell-heartbeat every 2s (see shell.qml); two
# stale checks in a row (the second one rules out "just resumed from
# suspend") get it SIGKILLed and started again. It also restarts
# quickshell when it's gone altogether (crashed), after two checks in a row
# find no process — `quickshell -n` makes that safe to race with sway's
# own exec_always on reload. If the session was locked (LockScreen.qml
# keeps quickshell-locked at 1/0), the new instance re-locks; dots-lock
# makes sure of it, with swaylock if the lock screen doesn't come up.
#
# Broken configs: quickshell's own log says whether an instance's config
# loaded. Each one that did is snapshotted (through the stow symlinks) to
# ~/.local/state/dots/quickshell-good; one that didn't is killed and the
# snapshot started instead, with a swaynag saying so. When the live config
# loads again (after a fix and a restart), the snapshot instance is retired.
#
# Runs as qs-watchdog.service under dots-session.target; the flock keeps it
# to one instance. QS_WATCHDOG_LIB=1 when sourcing defines the functions
# without running anything (tests/test-qs-watchdog.sh); QS_RUN, QS_GOOD and
# QS_LIVE override the paths for the same reason.

run="${QS_RUN:-${XDG_RUNTIME_DIR:-/tmp}}"
heartbeat="$run/quickshell-heartbeat"
lockflag="$run/quickshell-locked"
good="${QS_GOOD:-$HOME/.local/state/dots/quickshell-good}"
live="${QS_LIVE:-$HOME/.config/quickshell}"
stale=10
# Same launch line as sway's exec_always (QML2_IMPORT_PATH loads the rice
# Colors singleton); swaymsg exec runs it with sway's environment.
start="env QML2_IMPORT_PATH=$HOME/.rice $HOME/.local/bin/quickshell -n"
# instances whose config state was already acted on
checked=""

list_instances() { pgrep -x quickshell; }

# loaded | failed | pending, from quickshell's own per-instance log
config_state() {
    log="$run/quickshell/by-pid/$1/log.log"
    if grep -q 'Failed to load configuration' "$log" 2>/dev/null; then
        echo failed
    elif grep -q 'Configuration Loaded' "$log" 2>/dev/null; then
        echo loaded
    else
        echo pending
    fi
}

# whether instance $1 runs the snapshot rather than the live config
is_fallback() { tr '\0' '\n' <"/proc/$1/cmdline" 2>/dev/null | grep -qxF "$good"; }

# Copy the live config, through its symlinks, over the snapshot when they
# differ. Built next to it and moved into place, so a failed copy never
# leaves a half snapshot.
snapshot() {
    diff -rq "$live" "$good" >/dev/null 2>&1 && return 0
    rm -rf "$good.new"
    mkdir -p "$good.new" && cp -rL "$live/." "$good.new/" || { rm -rf "$good.new"; return 1; }
    rm -rf "$good" && mv "$good.new" "$good"
}

nag() { swaymsg -q exec "swaynag -t warning -m \"$1\""; }

fall_back() {
    if [ -f "$good/shell.qml" ]; then
        logger -t qs-watchdog "quickshell config failed to load ($1); starting the last good one"
        swaymsg -q exec "$start -p $good"
        nag "quickshell's config failed to load, running the last good one. Log: $1"
    else
        logger -t qs-watchdog "quickshell config failed to load ($1); no last-good copy to fall back to"
        nag "quickshell's config failed to load and there's no last-good copy yet. Log: $1. From a TTY: dots-rescue"
    fi
}

# One pass over the running instances: a live-config one that loaded is
# snapshotted and retires any snapshot instance; one that failed is killed
# and replaced by the snapshot (unless one already runs).
check_configs() {
    fallback=""
    for p in $(list_instances); do
        is_fallback "$p" && fallback=$p
    done
    for p in $(list_instances); do
        is_fallback "$p" && continue
        case " $checked " in *" $p "*) continue ;; esac
        case $(config_state "$p") in
            loaded)
                checked="$checked $p"
                snapshot
                if [ -n "$fallback" ]; then
                    logger -t qs-watchdog "live quickshell config loads again; stopping the last-good instance"
                    kill -KILL "$fallback"
                    fallback=""
                fi
                ;;
            failed)
                checked="$checked $p"
                kill -KILL "$p"
                [ -n "$fallback" ] || fall_back "$run/quickshell/by-pid/$p/log.log"
                ;;
        esac
    done
}

restart() {
    sleep 1
    swaymsg -q exec "$start"
    # the new instance locks again from the flag once it loads; dots-lock
    # gives it 10s, then locks with swaylock instead
    if [ "$(cat "$lockflag" 2>/dev/null)" = 1 ]; then
        DOTS_LOCK_WAIT=100 "$HOME/.local/bin/dots-lock"
    fi
}

[ -n "${QS_WATCHDOG_LIB:-}" ] && return 0

# Wait for the lock rather than exit: exiting made Restart=always respawn
# this every 2s for as long as another copy (e.g. one a pre-systemd sway
# started, which outlives its session) held it. Waiting, it takes over as
# soon as that copy goes.
exec 9>"$run/qs-watchdog.lock"
flock 9

strikes=0
missing=0
while sleep 3; do
    check_configs
    if ! pid=$(pgrep -xo quickshell); then
        strikes=0
        missing=$((missing + 1))
        [ "$missing" -ge 2 ] || continue
        logger -t qs-watchdog "quickshell not running (crashed?), restarting"
        restart
        missing=0
        continue
    fi
    missing=0
    [ -f "$heartbeat" ] || continue
    now=$(date +%s)
    # a fresh instance hasn't written its first heartbeat yet
    [ "$(ps -o etimes= -p "$pid" | tr -d ' ')" -gt "$stale" ] 2>/dev/null || { strikes=0; continue; }
    if [ $((now - $(stat -c %Y "$heartbeat"))) -gt "$stale" ]; then
        strikes=$((strikes + 1))
    else
        strikes=0
    fi
    [ "$strikes" -ge 2 ] || continue

    # keep the hung instance's log (it lives in tmpfs) for a post-mortem:
    # `qs log ~/.cache/qs-watchdog/<time>/log.qslog`
    keep="$HOME/.cache/qs-watchdog/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$keep" && cp "$run/quickshell/by-pid/$pid/"log.* "$keep/" 2>/dev/null
    logger -t qs-watchdog "quickshell ($pid) unresponsive, restarting; log kept in $keep"
    kill -KILL "$pid"
    restart
    strikes=0
done
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test-qs-watchdog.sh && bash tests/test-dots-lock.sh`
Expected: all `ok`.

- [ ] **Step 5: Apply to the live watchdog and check the snapshot appears**

```bash
systemctl --user restart qs-watchdog.service
sleep 8
ls ~/.local/state/dots/quickshell-good/shell.qml && diff -rq ~/.config/quickshell ~/.local/state/dots/quickshell-good && echo "snapshot matches live"
```
Expected: `snapshot matches live`.

- [ ] **Step 6: Commit**

```bash
git add scripts/.local/bin/qs-watchdog tests/test-qs-watchdog.sh
git commit -m "qs-watchdog: fall back to the last good quickshell config

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: sway-session in the repo, with a safe-mode retry

**Files:**
- Create: `.bootstrap/sway-session` (from `/usr/local/bin/sway-session`, tail changed)
- Create: `.bootstrap/sway.desktop` (copy of `/usr/local/share/wayland-sessions/sway.desktop`)
- Create: `tests/test-sway-session.sh`
- Modify: `install.sh` (new `install_sway_session`, called after `install_pam_lock_config`; doctor check)

**Interfaces:**
- Produces: `sway-session` honours `SWAY_SESSION_FAST_FAIL` (seconds, default 10) and `SWAY_SESSION_SAFE_CONFIG` (default `/etc/sway/config`), logs to `${XDG_STATE_HOME:-$HOME/.local/state}/sway.log`.

- [ ] **Step 1: Write the failing test**

`tests/test-sway-session.sh`:
```bash
#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

# sway stub: SWAY_STUB fast-fail | slow-fail | ok | safe-ok (fails unless given -c)
stub sway '
echo "sway $*" >>"$CALLS"
case "$SWAY_STUB" in
    fast-fail) exit 1 ;;
    slow-fail) sleep 3; exit 1 ;;
    ok) exit 0 ;;
    safe-ok) case "$*" in *"-c "*) exit 0 ;; *) exit 1 ;; esac ;;
esac'
# 2s threshold vs instant/3s stubs: date +%s has 1s resolution, so an
# instant failure can still read as 1s
export XDG_STATE_HOME=$TMP/state SWAY_SESSION_FAST_FAIL=2 SWAY_SESSION_SAFE_CONFIG=/safe/config
S=$REPO/.bootstrap/sway-session

: >"$CALLS"; SWAY_STUB=ok "$S"; rc=$?
check "clean exit: sway run once" [ "$(grep -c '^sway' "$CALLS")" = 1 ]
check "clean exit: status 0" [ "$rc" = 0 ]

: >"$CALLS"; SWAY_STUB=safe-ok "$S"; rc=$?
check "fast failure: retried with the safe config" called "-c /safe/config"
check "fast failure: safe mode's status returned" [ "$rc" = 0 ]
check "fast failure: logged" grep -q "safe mode" "$XDG_STATE_HOME/sway.log"

: >"$CALLS"; SWAY_STUB=fast-fail "$S"; rc=$?
check "safe mode fails too: back to GDM (non-zero)" [ "$rc" != 0 ]
check "safe mode fails too: only one retry" [ "$(grep -c '^sway' "$CALLS")" = 2 ]

: >"$CALLS"; SWAY_STUB=slow-fail "$S"; rc=$?
check "failure after a long session: no retry" [ "$(grep -c '^sway' "$CALLS")" = 1 ]
check "failure after a long session: status kept" [ "$rc" != 0 ]

finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-sway-session.sh`
Expected: FAIL (`.bootstrap/sway-session` doesn't exist).

- [ ] **Step 3: Bring sway-session into the repo with the retry**

```bash
cp /usr/local/bin/sway-session .bootstrap/sway-session
cp /usr/local/share/wayland-sessions/sway.desktop .bootstrap/sway.desktop
```
In `.bootstrap/sway-session`, update the header's first two lines to:
```sh
# Starts sway from GDM's "Sway" entry. Lives in ~/.dots/.bootstrap;
# install.sh installs it to /usr/local/bin (the stock sway.desktop is
# overridden in /usr/local/share/wayland-sessions).
```
and replace the last line (`exec sway "$@" 2>>"$log"`) with:
```sh
# Not exec'd: if sway dies within SWAY_SESSION_FAST_FAIL seconds it never
# really started (bad config, driver trouble), so try once more with the
# distro's stock config — its own bar, a terminal on $mod+Return — to
# get a session to fix things from. A second failure returns to GDM,
# where GNOME is still there.
fast_fail="${SWAY_SESSION_FAST_FAIL:-10}"
safe_config="${SWAY_SESSION_SAFE_CONFIG:-/etc/sway/config}"
started=$(date +%s)
status=0
sway "$@" 2>>"$log" || status=$?
[ "$status" -eq 0 ] && exit 0
if [ $(($(date +%s) - started)) -ge "$fast_fail" ]; then
    exit "$status"
fi
echo "sway exited ($status) within ${fast_fail}s; retrying in safe mode with $safe_config" >>"$log"
exec sway -c "$safe_config" "$@" 2>>"$log"
```
(`|| status=$?` keeps `set -eu` from exiting on sway's failure.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test-sway-session.sh`
Expected: all `ok`.

- [ ] **Step 5: install.sh installs it; --doctor checks it**

In `install.sh`, after `install_pam_lock_config() { ... }`, add:
```bash
# GDM's Sway entry runs /usr/local/bin/sway-session (GPU selection, a log
# GDM would otherwise discard, a safe-mode retry when sway dies at
# startup); the .desktop override points GDM at it. System paths, so sudo;
# only rewritten when they differ from the repo's.
install_sway_session() {
    local src dest
    for src in sway-session:/usr/local/bin/sway-session:755 \
               sway.desktop:/usr/local/share/wayland-sessions/sway.desktop:644; do
        dest=${src#*:}; dest=${dest%:*}
        cmp -s "$BOOTSTRAP_DIR/${src%%:*}" "$dest" && continue
        echo "==> installing $dest"
        sudo install -D -m "${src##*:}" "$BOOTSTRAP_DIR/${src%%:*}" "$dest"
    done
}
```
In the main sequence add `install_sway_session` on the line after `install_pam_lock_config`. In `doctor()`, after the `lock screen PAM service` line, add:
```bash
    if cmp -s "$BOOTSTRAP_DIR/sway-session" /usr/local/bin/sway-session \
        && cmp -s "$BOOTSTRAP_DIR/sway.desktop" /usr/local/share/wayland-sessions/sway.desktop; then
        ok "sway-session (GDM entry)"
    else
        bad "/usr/local/bin/sway-session or its GDM entry differs from .bootstrap (run install.sh)"
    fi
```

- [ ] **Step 6: Verify**

Run: `bash -n install.sh && ./install.sh --doctor | grep sway-session`
Expected: `FAIL ... sway-session ... differs` (the installed copy is still the old one; the user installs it in Task 6, needs sudo).

- [ ] **Step 7: Commit**

```bash
git add .bootstrap/sway-session .bootstrap/sway.desktop tests/test-sway-session.sh install.sh
git commit -m "sway-session: track it in the repo, retry in safe mode when sway dies at startup

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: dots-reload refuses a sway config that fails `sway -C`

**Files:**
- Modify: `scripts/.local/bin/dots-reload`
- Modify: `install.sh` (`doctor()`, "running configs" section)
- Create: `tests/test-dots-reload.sh`

**Interfaces:**
- Produces: `dots-reload` honours `DOTS_SWAY_CONFIG` (default `$HOME/.config/sway/config`).

- [ ] **Step 1: Write the failing test**

`tests/test-dots-reload.sh`:
```bash
#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

command -v sway >/dev/null || { echo "  skip  (no sway binary)"; exit 0; }
stub swaymsg 'case "$*" in *get_version*) exit 0 ;; esac; echo "swaymsg $*" >>"$CALLS"'
stub pkill 'echo "pkill $*" >>"$CALLS"'

cp "$HOME/.config/sway/config" "$TMP/good.conf"
{ cat "$HOME/.config/sway/config"; echo "floating_modifier nope nope"; } >"$TMP/bad.conf"

: >"$CALLS"; DOTS_SWAY_CONFIG=$TMP/good.conf "$BIN/dots-reload" sway >/dev/null 2>&1
check "valid config: sway reloaded" called "reload"

: >"$CALLS"; out=$(DOTS_SWAY_CONFIG=$TMP/bad.conf "$BIN/dots-reload" sway 2>&1)
check "broken config: no reload" not_called "reload"
check "broken config: says why" grep -q "not reloading sway" <<<"$out"

: >"$CALLS"; DOTS_SWAY_CONFIG=$TMP/bad.conf "$BIN/dots-reload" quickshell >/dev/null 2>&1
check "broken config: quickshell not killed (no reload to respawn it)" not_called "pkill"

finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-dots-reload.sh`
Expected: FAIL on "broken config: no reload" and the next two.

- [ ] **Step 3: Add the check to dots-reload**

In `scripts/.local/bin/dots-reload`, after `sway_up() { ... }` add:
```sh
sway_config="${DOTS_SWAY_CONFIG:-$HOME/.config/sway/config}"

# A reload with a broken config applies what parses and drops the rest;
# keep the running config instead. --unsupported-gpu: without it the
# check always fails on the NVIDIA driver.
sway_config_ok() {
    out=$(sway --unsupported-gpu -C -c "$sway_config" 2>&1) && return 0
    echo "warning: $sway_config has errors; not reloading sway (the running config stays):" >&2
    printf '%s\n' "$out" | grep -i 'error' | grep -viE 'nvidia|nouveau|proprietary' >&2
    return 1
}
```
and right after the existing block that clears `quickshell`/`sway`/`wallpaper` when sway is unreachable, add:
```sh
# quickshell's restart needs the reload (exec_always respawns it)
if [ -n "$quickshell$sway" ] && ! sway_config_ok; then
    quickshell=; sway=
fi
```
Update the header comment's usage block to mention: `sway is only reloaded when its config passes sway -C.`

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test-dots-reload.sh`
Expected: all `ok`.

- [ ] **Step 5: --doctor checks the sway config**

In `install.sh` `doctor()`, inside the `if swaymsg -t get_version ...` block of "running configs", before the sway `get_config` comparison, add:
```bash
        if sway --unsupported-gpu -C >/dev/null 2>&1; then
            ok "sway config valid (sway -C)"
        else
            bad "sway config has errors (sway --unsupported-gpu -C); dots-reload won't reload it"
        fi
```
Run: `./install.sh --doctor | grep 'sway config'`
Expected: `ok    sway config valid (sway -C)` and `ok    sway config current`.

- [ ] **Step 6: Commit**

```bash
git add scripts/.local/bin/dots-reload install.sh tests/test-dots-reload.sh
git commit -m "dots-reload: don't reload a sway config that fails sway -C

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: dots-rescue, and a README section

**Files:**
- Create: `scripts/.local/bin/dots-rescue`
- Create: `tests/test-dots-rescue.sh`
- Modify: `README.md` (new "When things break" section after "### Checking a machine")

**Interfaces:**
- Consumes: snapshot at `~/.local/state/dots/quickshell-good` (Task 2), `swaylock` (Task 1).
- Produces: `dots-rescue quickshell|quickshell-good|quickshell-revert|sway-reload|sway-exit|lock-prompt`. Env overrides: `DOTS_RESCUE_RUNDIR` (default `/run/user/$(id -u)`), `DOTS_DIR` (default `$HOME/.dots`), `QS_GOOD`.

- [ ] **Step 1: Write the failing test**

`tests/test-dots-rescue.sh`:
```bash
#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

stub swaymsg 'echo "swaymsg SWAYSOCK=$SWAYSOCK $*" >>"$CALLS"'
stub pkill 'echo "pkill $*" >>"$CALLS"'
R=$BIN/dots-rescue
export DOTS_RESCUE_RUNDIR=$TMP/run QS_GOOD=$TMP/good
mkdir -p "$DOTS_RESCUE_RUNDIR" "$QS_GOOD"
touch "$QS_GOOD/shell.qml"

# a live "sway" (a real process) with an older socket, a dead one newer
sleep 30 & live=$!
touch -d '-2 min' "$DOTS_RESCUE_RUNDIR/sway-ipc.$(id -u).$live.sock"
touch "$DOTS_RESCUE_RUNDIR/sway-ipc.$(id -u).999999.sock"

"$R" sway-reload
check "stale sockets skipped: the live sway's used" called "SWAYSOCK=$DOTS_RESCUE_RUNDIR/sway-ipc.$(id -u).$live.sock reload"

: >"$CALLS"; "$R" quickshell-good >/dev/null
check "quickshell-good: old instance killed" called "pkill -KILL -x quickshell"
check "quickshell-good: snapshot started" called "-p $QS_GOOD"

: >"$CALLS"; "$R" lock-prompt >/dev/null
check "lock-prompt: swaylock started in the session" called "exec swaylock -f"

# revert stashes (not discards) uncommitted quickshell/ changes
export DOTS_DIR=$TMP/dots
git init -q "$DOTS_DIR"; mkdir -p "$DOTS_DIR/quickshell"
echo committed >"$DOTS_DIR/quickshell/f"
git -C "$DOTS_DIR" add -A; git -C "$DOTS_DIR" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm init
echo broken >"$DOTS_DIR/quickshell/f"
: >"$CALLS"; "$R" quickshell-revert >/dev/null
check "revert: working tree back to committed" [ "$(cat "$DOTS_DIR/quickshell/f")" = committed ]
check "revert: change kept in a stash" git -C "$DOTS_DIR" stash list --format=%s | grep -q "dots-rescue"
check "revert: quickshell restarted" called "pkill -KILL -x quickshell"

"$R" >/dev/null 2>&1
check "no subcommand: usage, non-zero" [ $? != 0 ]

kill "$live"
rm "$DOTS_RESCUE_RUNDIR"/sway-ipc.*
"$R" sway-reload >/dev/null 2>&1
check "no sway running: fails" [ $? != 0 ]

finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-dots-rescue.sh`
Expected: FAIL (dots-rescue doesn't exist).

- [ ] **Step 3: Write dots-rescue**

`scripts/.local/bin/dots-rescue`:
```sh
#!/bin/sh
# Recovery for a wedged session, from a TTY (Ctrl+Alt+F3) or over ssh:
#
#   dots-rescue quickshell          restart quickshell (qs-watchdog brings it back)
#   dots-rescue quickshell-good     run the last quickshell config that loaded
#   dots-rescue quickshell-revert   stash uncommitted quickshell/ changes in ~/.dots, restart
#   dots-rescue sway-reload         reload sway's config
#   dots-rescue sway-exit           end the sway session (back to the login screen)
#   dots-rescue lock-prompt         locked with no password prompt: start swaylock
#
# A TTY has no SWAYSOCK, so the running sway's socket is looked up here.
# DOTS_RESCUE_RUNDIR, DOTS_DIR and QS_GOOD override paths for tests.
rundir="${DOTS_RESCUE_RUNDIR:-/run/user/$(id -u)}"
dots="${DOTS_DIR:-$HOME/.dots}"
good="${QS_GOOD:-$HOME/.local/state/dots/quickshell-good}"
start="env QML2_IMPORT_PATH=$HOME/.rice $HOME/.local/bin/quickshell -n"

usage() {
    sed -n '4,9p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 1
}

# sway-ipc.<uid>.<pid>.sock, newest first, skipping ones whose sway is gone
find_sway() {
    for sock in $(ls -t "$rundir"/sway-ipc.*.sock 2>/dev/null); do
        pid=${sock%.sock}
        pid=${pid##*.}
        kill -0 "$pid" 2>/dev/null && { echo "$sock"; return 0; }
    done
    return 1
}

need_sway() {
    SWAYSOCK=$(find_sway) || { echo "dots-rescue: no running sway found" >&2; exit 1; }
    export SWAYSOCK
}

case "${1:-}" in
    quickshell)
        pkill -KILL -x quickshell
        echo "killed quickshell; qs-watchdog starts it again within ~6s"
        ;;
    quickshell-good)
        [ -f "$good/shell.qml" ] || { echo "dots-rescue: no last-good config at $good" >&2; exit 1; }
        need_sway
        pkill -KILL -x quickshell
        swaymsg -q exec "$start -p $good"
        echo "started the last-good quickshell config ($good)"
        ;;
    quickshell-revert)
        git -C "$dots" stash push -m "dots-rescue quickshell-revert" -- quickshell/ || exit 1
        pkill -KILL -x quickshell
        echo "stashed uncommitted quickshell/ changes (git -C $dots stash pop brings them back); quickshell restarting"
        ;;
    sway-reload) need_sway; swaymsg reload ;;
    sway-exit) need_sway; swaymsg exit ;;
    lock-prompt)
        need_sway
        swaymsg -q exec "swaylock -f"
        echo "swaylock started in the sway session"
        ;;
    *) usage ;;
esac
```
Then `chmod +x scripts/.local/bin/dots-rescue tests/test-*.sh`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test-dots-rescue.sh`
Expected: all `ok`.

- [ ] **Step 5: README section**

In `README.md`, after the "### Checking a machine" section, add:
```markdown
### When things break

- **quickshell's config doesn't load:** `qs-watchdog` runs the last config
  that did (`~/.local/state/dots/quickshell-good`) and says so in a
  swaynag. Fix the config and run `dots-reload quickshell`; once it loads,
  the fallback is stopped.
- **Locking:** everything locks through `dots-lock`, which uses swaylock
  when quickshell's lock screen doesn't come up.
- **sway dies at startup:** `sway-session` retries once with the stock
  `/etc/sway/config` (safe mode); see `~/.local/state/sway.log`. If that
  fails too you're back at the login screen, where GNOME still works.
  `dots-reload` won't reload a sway config that fails `sway -C`.
- **The session is wedged:** switch to a TTY (Ctrl+Alt+F3) or ssh in and
  run `dots-rescue` for the options (restart or roll back quickshell,
  reload or exit sway, get a swaylock prompt).
```

- [ ] **Step 6: Commit**

```bash
git add scripts/.local/bin/dots-rescue tests/test-dots-rescue.sh README.md
git commit -m "dots-rescue: TTY/ssh recovery commands; README: when things break

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Full verification and hand-over

**Files:** none new.

- [ ] **Step 1: Everything green**

```bash
bash tests/run.sh
mapfile -t s < <(git ls-files --cached --others --exclude-standard | while IFS= read -r f; do [ -f "$f" ] && head -n1 "$f" | grep -Eq '^#!.*\b(ba)?sh\b' && echo "$f"; done)
shellcheck --severity=warning --external-sources "${s[@]}"
```
Expected: all tests `ok`; shellcheck prints nothing. (If shellcheck isn't installed yet: `python3 -m venv /tmp/sc && /tmp/sc/bin/pip install -q shellcheck-py` and use `/tmp/sc/bin/shellcheck`.)

- [ ] **Step 2: Live state**

```bash
stow -v --no-folding -t "$HOME" scripts sway quickshell
systemctl --user daemon-reload
systemctl --user restart swayidle.service qs-watchdog.service
./install.sh --doctor
```
Expected: no new FAIL besides `sway-session ... differs` (needs sudo) and ShellCheck/swaylock "not installed" if the user hasn't run install.sh yet.

- [ ] **Step 3: Push, and hand the user the checks only they can do**

`git push`, then ask the user to:
1. Run `./install.sh` (sudo: installs swaylock, ShellCheck, the new sway-session).
2. `$mod+Escape`, unlock: quickshell's lock screen as before.
3. `dots-rescue lock-prompt` from a terminal: swaylock appears; unlock it.
4. Optional: break `shell.qml` on purpose (add a stray `}`), `dots-reload quickshell`, see the swaynag and the last-good bar; revert, `dots-reload quickshell`, the fallback goes away.
