#!/usr/bin/env bash
# tmux-sessionizer — session/window/pane tree popup with freeze/thaw.
#
# Binds no keys itself. It registers a `sessionizer` command alias, so any
# config can do:   bind -n M-s sessionizer
#
# Options (all optional):
#   @sessionizer-width         popup width   (default 80%)
#   @sessionizer-height        popup height  (default 70%)
#   @sessionizer-border-style  popup border  (default fg=#{@color-neon}, blue if unset)
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

opt() { local v; v=$(tmux show -gqv "$1"); echo "${v:-$2}"; }

w=$(opt @sessionizer-width 80%)
h=$(opt @sessionizer-height 70%)
border=$(opt @sessionizer-border-style 'fg=#{?#{@color-neon},#{@color-neon},blue}')

# fixed index: re-sourcing the config replaces the alias instead of piling up
tmux set -s 'command-alias[200]' \
    "sessionizer=display-popup -E -w $w -h $h -b rounded -S \"$border\" -T ' sessions ' '$CURRENT_DIR/scripts/sessionizer.sh'"
