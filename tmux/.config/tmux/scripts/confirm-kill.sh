#!/usr/bin/env bash
# Confirm-and-kill popup for a pane or window: tints the target red while the
# prompt is up, resets on any answer, kills only on `y`.
#
#   confirm-kill.sh pane|window [ID]
#
# With no ID it takes the client's active pane/window (popup commands aren't
# format-expanded, so the binds can't pass one; `tmux display` inside a popup
# resolves to the pane underneath).
#
# confirm-before can't do this: a cancelled prompt drops the rest of the
# command chain, so there'd be nothing left to undo the highlight.
# Colors come from the @color-* options (apply-theme), with fallbacks.
kind=$1
id=${2:-$(tmux display -p "#{${kind}_id}")}

color() { local v; v=$(tmux show -gqv "@color-$1" 2>/dev/null || true); echo "${v:-$2}"; }
fg() { printf '\033[38;2;%d;%d;%dm' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"; }

red=$(color red '#e8606e') bg=$(color black '#0a0f1a') gray=$(color gray '#56657d') txt=$(color fg '#dce6f5')
# ~25% of the alert color over the background: visible, text stays readable
# shellcheck disable=SC2046,SC2183 # word-split on purpose: one arg per channel
tint=$(printf '#%02x%02x%02x' $(for i in 1 3 5; do
    echo $(((0x${red:$i:2} * 25 + 0x${bg:$i:2} * 75) / 100))
done))

mapfile -t panes < <(if [ "$kind" = pane ]; then echo "$id"; else tmux list-panes -t "$id" -F '#{pane_id}'; fi)

clear_tint() {
    local p
    for p in "${panes[@]}"; do tmux set -pu -t "$p" window-style \; set -pu -t "$p" window-active-style; done
    [ "$kind" = window ] && tmux set -wu -t "$id" window-status-current-style
}
trap clear_tint EXIT

for p in "${panes[@]}"; do
    tmux set -p -t "$p" window-style "bg=$tint" \; set -p -t "$p" window-active-style "bg=$tint"
done
[ "$kind" = window ] && tmux set -w -t "$id" window-status-current-style "bg=$red,fg=$bg,bold"

if [ "$kind" = pane ]; then
    what=$(tmux display -p -t "$id" 'pane #{pane_index}  #{pane_current_command}  #{pane_current_path}')
else
    what=$(tmux display -p -t "$id" 'window #{window_index}: #{window_name}  (#{window_panes} panes)')
fi

printf '\n  %s\033[1mkill %s?\033[0m\n\n  %s%s\033[0m\n\n  %s\033[1my\033[0m%s kill    \033[0m%s\033[1many other key\033[0m%s cancel\033[0m' \
    "$(fg "$red")" "$kind" "$(fg "$txt")" "$what" "$(fg "$red")" "$(fg "$gray")" "$(fg "$txt")" "$(fg "$gray")"

read -rsn1 key
if [ "$key" = y ]; then
    clear_tint
    trap - EXIT
    tmux "kill-$kind" -t "$id"
fi
