#!/usr/bin/env bash
# Opt-in extras: features that aren't part of the base dotfiles and only
# get installed and linked in on machines that ask for them.
#
#   extras.sh list              available extras, * = enabled here
#   extras.sh enable <name>     run <name>/setup.sh, stow it, restart quickshell
#   extras.sh disable <name>    unstow it (leaves installed packages alone)
#   extras.sh restow            re-link every enabled extra (install.sh does this)
#
# Each extra is a directory here holding a setup.sh (installs
# dependencies; idempotent) and/or a stow package `home/` mirroring $HOME.
# An extra's desktop half (e.g. a VPN's quickshell panel) lives in
# ~/.rice/desktop/extras/<name>/home and is linked only on the desktop
# profile (~/.config/dots/profile). Which extras are enabled is per
# machine, kept in the untracked ~/.dots/.extras-enabled.
set -euo pipefail

EXTRAS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENABLED_FILE="$EXTRAS_DIR/../.extras-enabled"
RICE_EXTRAS_DIR="${RICE_DIR:-$HOME/.rice}/desktop/extras"
PROFILE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dots/profile"

# The stow package dirs of extra $1: its own home/, plus its desktop half
# from ~/.rice on the desktop profile.
extra_dirs() {
    [ -d "$EXTRAS_DIR/$1/home" ] && echo "$EXTRAS_DIR/$1"
    if [ "$(cat "$PROFILE_FILE" 2>/dev/null)" = desktop ] && [ -d "$RICE_EXTRAS_DIR/$1/home" ]; then
        echo "$RICE_EXTRAS_DIR/$1"
    fi
    return 0
}

available() {
    local d
    for d in "$EXTRAS_DIR"/*/; do
        { [ -d "$d/home" ] || [ -f "$d/setup.sh" ]; } && basename "$d"
    done
}

enabled() {
    [ -f "$ENABLED_FILE" ] && grep -v '^\s*$' "$ENABLED_FILE" || true
}

is_enabled() {
    enabled | grep -x "$1" >/dev/null
}

require_extra() {
    if [ -z "${1:-}" ] || ! available | grep -x "$1" >/dev/null; then
        echo "error: unknown extra '${1:-}'; available: $(available | tr '\n' ' ')" >&2
        exit 1
    fi
}

stow_extra() {
    local dir
    for dir in $(extra_dirs "$1"); do
        stow -d "$dir" -t "$HOME" --no-folding "$2" home
    done
}

# --no-folding means stow -D leaves the extra's (now empty) directories
# behind, e.g. ~/.config/quickshell/extras/<name>.
prune_dirs() {
    local dir
    for dir in $(extra_dirs "$1"); do
        (cd "$dir/home" && find . -mindepth 1 -type d | sort -r) | while IFS= read -r d; do
            rmdir "$HOME/$d" 2>/dev/null || true
        done
    done
}

# Same as sway's $mod+Shift+c: quickshell only scans for extras at
# startup, and the watchdog/exec_always bring it straight back. Only for
# extras that actually add quickshell code.
restart_quickshell() {
    [ -n "$(extra_dirs "$1" | grep -F "$RICE_EXTRAS_DIR")" ] || return 0
    "$EXTRAS_DIR/../scripts/.local/bin/dots-reload" quickshell
}

# systemd timers an extra ships (home/.config/systemd/user/*.timer, e.g.
# backup's) are enabled once they're linked in, and disabled before they're
# unlinked so systemd isn't left with a dangling timers.target.wants link.
extra_timers() {
    local t
    for t in "$EXTRAS_DIR/$1"/home/.config/systemd/user/*.timer; do
        [ -e "$t" ] && basename "$t"
    done
    return 0
}

enable_timers() {
    local timers
    timers=$(extra_timers "$1")
    [ -n "$timers" ] || return 0
    systemctl --user daemon-reload
    # shellcheck disable=SC2086
    systemctl --user enable --now $timers
}

disable_timers() {
    local timers
    timers=$(extra_timers "$1")
    [ -n "$timers" ] || return 0
    # shellcheck disable=SC2086
    systemctl --user disable --now $timers || true
}

case "${1:-list}" in
    list)
        for name in $(available); do
            if is_enabled "$name"; then echo "* $name"; else echo "  $name"; fi
        done
        ;;
    enable)
        require_extra "${2:-}"
        name="$2"
        if [ -x "$EXTRAS_DIR/$name/setup.sh" ]; then
            echo "==> setting up $name"
            "$EXTRAS_DIR/$name/setup.sh"
        fi
        echo "==> stowing $name"
        stow_extra "$name" -R
        enable_timers "$name"
        is_enabled "$name" || echo "$name" >>"$ENABLED_FILE"
        restart_quickshell "$name"
        ;;
    disable)
        require_extra "${2:-}"
        name="$2"
        disable_timers "$name"
        echo "==> unstowing $name"
        stow_extra "$name" -D
        prune_dirs "$name"
        if [ -f "$ENABLED_FILE" ]; then
            grep -vx "$name" "$ENABLED_FILE" >"$ENABLED_FILE.tmp" || true
            mv "$ENABLED_FILE.tmp" "$ENABLED_FILE"
        fi
        restart_quickshell "$name"
        ;;
    restow)
        for name in $(enabled); do
            [ -d "$EXTRAS_DIR/$name" ] || continue
            echo "==> stowing extra $name"
            stow_extra "$name" -R
        done
        ;;
    *)
        sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
        exit 1
        ;;
esac
