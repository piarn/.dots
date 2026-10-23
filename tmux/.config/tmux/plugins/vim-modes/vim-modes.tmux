#!/bin/sh
# vim-modes — Normal / Visual / Insert modes for tmux.
#
# TPM-style entry point: load it from tmux.conf with
#   run-shell ~/.config/tmux/plugins/vim-modes/vim-modes.tmux
# placed *after* TPM's own `run`, so bindings that overlap with other plugins
# (notably tmux-yank's copy-mode keys) resolve in this plugin's favour.
#
# This script only does the parts that depend on user options; the key tables
# themselves live in vim-modes.conf and are loaded through tmux's own parser,
# because chained (`\;`) bindings cannot survive being built in a shell.
set -eu

CURRENT_DIR=$(dirname "$(readlink -f "$0")")

tmux_option() {
    value=$(tmux show-option -gqv "$1")
    if [ -z "$value" ]; then
        printf '%s' "$2"
    else
        printf '%s' "$value"
    fi
}

# `,` and `}` end a field inside `#{?cond,then,else}`, so any user-supplied text
# or style that contains one has to be escaped or the whole conditional falls
# apart at draw time.
escape_format() {
    printf '%s' "$1" | sed -e 's/,/#,/g' -e 's/}/#}/g'
}

# -> `#[fg=...]TEXT#[default]`, or bare TEXT when no style is configured (the
# default: theme.conf owns the colours, this plugin only owns the words).
segment() {
    text=$(escape_format "$1")
    style=$(escape_format "$2")
    if [ -z "$style" ]; then
        printf '%s' "$text"
    else
        printf '#[%s]%s#[default]' "$style" "$text"
    fi
}

normal=$(segment "$(tmux_option '@vim-modes-normal-text' ' NORMAL ')" \
                 "$(tmux_option '@vim-modes-normal-style' '')")
visual=$(segment "$(tmux_option '@vim-modes-visual-text' ' VISUAL ')" \
                 "$(tmux_option '@vim-modes-visual-style' '')")
insert=$(segment "$(tmux_option '@vim-modes-insert-text' ' INSERT ')" \
                 "$(tmux_option '@vim-modes-insert-style' '')")

# VISUAL is tested first and off the pane's mode, not off the key table:
# copy-mode runs with the client on the root key table (see vim-modes.conf's
# header), so a key-table test alone would report VISUAL as INSERT. The test is
# `pane_in_mode` rather than `pane_mode == copy-mode` so that the other pane
# modes a leader key can open — a chooser, the clock, `prefix ?` — read as
# VISUAL too; what they have in common is that typing does not reach the shell,
# which is the thing the indicator is there to tell you.
indicator="#{?pane_in_mode,${visual},#{?#{==:#{client_key_table},root},${insert},${normal}}}"

tmux set-option -g @mode_indicator "$indicator"

# "Is this pane running an editor that speaks for itself?" — published as an
# option so vim-modes.conf can test it with `#{E:@vim-modes-vim-pane}` (E:
# expands a user option's value as a format) and keep its bindings static and
# chainable. Two bindings need it: Escape, which such a pane wants for its own
# insert->normal transition, and NORMAL's hjkl, which hands the matching
# vim-tmux-navigator chord over so a move can cross into a vim split instead of
# stopping at the tmux pane border.
passthrough=$(tmux_option '@vim-modes-escape-passthrough' 'nvim vim')
passthrough_re=$(printf '%s' "$passthrough" | tr -s ' ' '|')
tmux set-option -g @vim-modes-vim-pane "#{m/r:^(${passthrough_re})$,#{pane_current_command}}"

# Apps that want Escape for themselves but are not vim-navigator-aware (ssh into
# a box running vi, TUIs with menus). Escape goes to them; C-Space is the way
# back to NORMAL. Kept apart from the list above so NORMAL's hjkl still moves
# tmux panes over these instead of sending them C-h/j/k/l.
escape_apps=$(tmux_option '@vim-modes-escape-apps' '')
esc_re=$(printf '%s %s' "$passthrough" "$escape_apps" | tr -s ' ' '|' | sed 's/^|//; s/|$//')
tmux set-option -g @vim-modes-esc-pane "#{m/r:^(${esc_re})$,#{pane_current_command}}"

# --- the leader ------------------------------------------------------------
#
# The leader is tmux's own prefix, whatever the user set it to, and its commands
# live in tmux's own `prefix` key table. The option itself has to be parked on
# None though: tmux's built-in prefix check only fires while the client is on
# the *default* key table, which in this plugin is INSERT, so a live
# `prefix Space` would swallow the space bar mid-sentence. NORMAL reaches the
# table through an ordinary binding instead.
#
# The key is remembered in @vim-modes-leader so a reload — which re-runs this
# script against the None we ourselves set — doesn't lose it. Dropping the
# `set -g prefix` line from tmux.conf therefore keeps the last leader until the
# server restarts; set the option to the key you want rather than deleting it.
remember_leader() {
    key=$(tmux show-option -gv "$1")
    if [ "$key" = 'None' ]; then
        key=$(tmux_option "$2" "$3")
    fi
    tmux set-option -g "$2" "$key"
    tmux set-option -g "$1" None
    printf '%s' "$key"
}

# unbind the previous leader first, so changing it doesn't leave the old key
# bound; vim-modes.conf is sourced afterwards and restores anything this hits.
for stored in '@vim-modes-leader' '@vim-modes-leader2'; do
    old=$(tmux show-option -gqv "$stored")
    if [ -n "$old" ] && [ "$old" != 'None' ]; then
        tmux unbind-key -T vim-normal "$old"
    fi
done

leader=$(remember_leader prefix '@vim-modes-leader' 'C-b')
leader2=$(remember_leader prefix2 '@vim-modes-leader2' 'None')

# The trip back to NORMAL after a leader command, as a command alias so the
# bindings in vim-modes.conf can read as "do the thing, go back". It is
# conditional: a command that opened copy-mode, a chooser or the clock must
# leave the client on root for that mode's key table to be reachable at all, and
# pane-mode-changed returns those to NORMAL when the mode ends.
tmux set-option -s command-alias[100] \
    'vim-modes-return=if -F "#{?pane_in_mode,0,1}" "switch-client -T vim-normal"'

# Give every binding already in the prefix table that same return: tmux resets
# the key table to the default (root, i.e. INSERT) once a prefix command
# finishes, so without this, stock keys like `prefix ?` and other plugins'
# bindings would quietly drop you into INSERT. list-keys prints valid tmux
# syntax, so the table can be read out, extended and sourced back in. Bindings
# that already carry the return are skipped, which keeps reloads from stacking
# it up.
#
# `-r` (repeat) is dropped along the way. A repeat binding leaves the client
# flagged as repeating, and tmux sends a repeating client back to the *default*
# table on the next key regardless of what the binding switched to — so
# `prefix Left` would move a pane and then silently drop you into INSERT. The
# repeat itself is already gone once the return fires after the first press;
# dropping the flag is what keeps the mode right. NORMAL's own HJKL covers the
# resizing this mattered for.
#
# A binding that *starts* with confirm-before (stock `&` is the one that
# matters) gets the return put in front as well: confirm-before suspends the
# chain until the prompt is answered and answering with Escape drops the rest,
# so a trailing return alone would never run on a cancel and would strand the
# client in INSERT. Leaving the trailing one on too is harmless — on the
# confirmed path it just re-asserts a mode already set.
rewritten=$(mktemp)
tmux list-keys -T prefix \
    | grep -vF '#{?pane_in_mode,0,1}' \
    | sed -e 's|^bind-key  *-r  *-T |bind-key -T |' \
          -e 's|^\(bind-key  *-T prefix  *[^ ][^ ]*  *\)\(confirm-before .*\)$|\1vim-modes-return \\; \2|' \
          -e 's|$| \\; vim-modes-return|' > "$rewritten"
tmux source-file "$rewritten"
rm -f "$rewritten"

tmux source-file "$CURRENT_DIR/vim-modes.conf"

tmux bind-key -T vim-normal "$leader" switch-client -T prefix
if [ "$leader2" != 'None' ]; then
    tmux bind-key -T vim-normal "$leader2" switch-client -T prefix
fi


# Prepend the indicator to status-left unless the user places `#{E:@mode_indicator}`
# themselves and sets @vim-modes-auto-status 'off'. Re-running this script is
# idempotent: sourcing tmux.conf resets status-left first, and the guard below
# covers the case where it doesn't.
if [ "$(tmux_option '@vim-modes-auto-status' 'on')" = 'on' ]; then
    status_left=$(tmux show-option -gv status-left)
    case "$status_left" in
        *'@mode_indicator'*) ;;
        *) tmux set-option -g status-left "#{E:@mode_indicator}${status_left}" ;;
    esac
fi
