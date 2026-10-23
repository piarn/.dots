#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

stub tmux 'echo "tmux $*" >>"$CALLS"'
stub pgrep 'exit 1'
stub rice 'echo "rice $*" >>"$CALLS"'
export DOTS_RICE_RELOAD=$TMP/stubs/rice

: >"$CALLS"; "$BIN/dots-reload" tmux >/dev/null 2>&1
check "tmux: config re-sourced" called "tmux source-file"
check "tmux alone: desktop left alone" not_called "rice"

: >"$CALLS"; "$BIN/dots-reload" sway quickshell >/dev/null 2>&1
check "desktop targets handed to rice-reload" called "rice sway quickshell"
check "desktop alone: tmux left alone" not_called "tmux source-file"

: >"$CALLS"; "$BIN/dots-reload" >/dev/null 2>&1
check "no targets: everything" called "rice quickshell sway"

: >"$CALLS"; DOTS_RICE_RELOAD=$TMP/nope "$BIN/dots-reload" sway >/dev/null 2>&1; rc=$?
check "terminal profile (no rice-reload): desktop skipped quietly" [ "$rc" -eq 0 ]

check "unknown target rejected" not "$BIN/dots-reload" bogus 2>/dev/null

finish
