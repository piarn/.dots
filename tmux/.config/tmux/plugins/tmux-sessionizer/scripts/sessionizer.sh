#!/usr/bin/env bash
# tmux session tree for "one session per case": running and frozen sessions,
# each expanded into windows and panes. Enter jumps to the selected node
# (thawing a frozen session first).
#
#   enter   jump to session / window / pane        ctrl-f  freeze session: snapshot + kill
#   ctrl-r  rename session / window / pane (or a frozen session / window)
#   ctrl-x  kill session/window/pane, or discard a frozen one
#   ctrl-n  new session named by the query
#
# Frozen = a per-session snapshot cut out of tmux-resurrect's newest save
# (windows, layouts, cwds; nvim/lazygit are relaunched) into $FROZEN, so it
# survives continuum's autosaves overwriting `last`. Thawing rebuilds it and
# deletes the snapshot.
#
# Meant to run inside a tmux popup (see sessionizer.tmux, bind it with `sessionizer`), so
# it can end with `tmux switch-client` and have that land on the real client.
# Colors come from the @color-* tmux options (~/.config/tmux/theme.conf), so they
# follow apply-theme.
set -euo pipefail

DATA=${XDG_DATA_HOME:-$HOME/.local/share}/tmux
FROZEN=$DATA/frozen
RESURRECT=$DATA/resurrect
[ -d "$RESURRECT" ] || RESURRECT=$HOME/.tmux/resurrect
SAVE_SH=$(dirname "${BASH_SOURCE[0]}")/../../tmux-resurrect/scripts/save.sh   # sibling tpm plugin
US=$'\037'   # read can't keep empty tab-separated fields, this separator it can
mkdir -p "$FROZEN"

# theme color (#rrggbb) by role, with a fallback if tmux hasn't got the option
color() { local v; v=$(tmux show -gqv "@color-$1" 2>/dev/null || true); echo "${v:-$2}"; }
# #rrggbb -> 24-bit foreground escape
fg() { printf '\033[38;2;%d;%d;%dm' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"; }

C_FG=$(color fg '#dce6f5') C_NEON=$(color neon '#3a86e0') C_ACID=$(color acid '#7cc0ff')
C_DIM=$(color dim '#1c2c47') C_GRAY=$(color gray '#56657d') C_SURFACE=$(color surface '#111a2b')

age() {
    local s=$(($(date +%s) - $(stat -c %Y "$1")))
    if [ "$s" -ge 86400 ]; then echo "$((s / 86400))d"
    elif [ "$s" -ge 3600 ]; then echo "$((s / 3600))h"
    else echo "$((s / 60))m"; fi
}

# Normalized rows (tab separated), one per pane:
#   session kind info nwin widx wname wact npanes pidx cmd path pact
# render() turns them into the tree: display \t type \t session \t target
render() {
    awk -F'\t' -v home="$HOME" \
        -v acid="$(fg "$C_ACID")" -v neon="$(fg "$C_NEON")" -v txt="$(fg "$C_FG")" \
        -v gray="$(fg "$C_GRAY")" -v tree="$(fg "$C_DIM")" '
    function short(p) { sub("^" home, "~", p); return p }
    {
        s = $1; kind = $2; w = $5; f = (kind == "F" ? "F" : "")
        if (s != cs) {
            cs = s; cw = ""; seenw = 0
            if (kind == "F")
                printf "%s❄ %s%s  %s%s · %s win\033[0m\tFS\t%s\t=%s\n", gray, txt, s, gray, $3, $4, s, s
            else
                printf "%s●%s %s\033[1m%s\033[0m  %s%s win%s\033[0m\tS\t%s\t=%s\n", acid, txt, "", s, gray, $4, ($3 == "" ? "" : " · " $3), s, s
        }
        if (w != cw) {
            cw = w; seenw++; seenp = 0; lastw = (seenw == $4)
            printf "%s  %s %s%s: %s  %s(%sp)\033[0m\t%sW\t%s\t=%s:%s\n",
                tree, (lastw ? "└─" : "├─"), ($7 == 1 ? acid : txt), w, $6, gray, $8, f, s, s, w
        }
        seenp++
        printf "%s  %s  %s %s%s %s%s  %s%s\033[0m\t%sP\t%s\t=%s:%s.%s\n",
            tree, (lastw ? " " : "│"), (seenp == $8 ? "└─" : "├─"),
            ($12 == 1 ? neon : gray), $9, txt, $10, gray, short($11), f, s, s, w, $9
    }'
}

# snapshot -> normalized rows (needs per-window pane counts, so two passes)
frozen_rows() {
    awk -F'\t' -v OFS='\t' -v s="$2" -v info="$3" '
        FNR == NR { if ($1 == "window") { nw++; wn[$3] = $4; wa[$3] = $5 } else if ($1 == "pane") np[$3]++; next }
        $1 == "pane" { n = wn[$3]; sub(/^:/, "", n); p = $8; sub(/^:/, "", p)
            print s, "F", info, nw, $3, n, wa[$3], np[$3], $6, $10, p, $9 }' "$1" "$1"
}

list() {
    local f name
    tmux list-panes -a -F "#{session_name}	S	#{?session_attached,attached,}	#{session_windows}	#{window_index}	#{window_name}	#{window_active}	#{window_panes}	#{pane_index}	#{pane_current_command}	#{pane_current_path}	#{pane_active}" 2>/dev/null | render || true
    for f in "$FROZEN"/*.txt; do
        [ -e "$f" ] || continue
        name=$(basename "$f" .txt)
        tmux has-session -t "=$name" 2>/dev/null && continue
        frozen_rows "$f" "$name" "frozen $(age "$f") ago" | render
    done
}

# killing the session this client sits in would drop the client out of tmux:
# move it to another session first, or refuse if there is none
leave() {
    [ "$(tmux display -p '#{session_name}')" = "$1" ] || return 0
    tmux switch-client -n 2>/dev/null && [ "$(tmux display -p '#{session_name}')" != "$1" ]
}

freeze() {
    local name=$1 last=$RESURRECT/last
    leave "$name" || return 1
    "$SAVE_SH" quiet >/dev/null 2>&1 || true
    awk -F'\t' -v s="$name" '($1=="pane" || $1=="window") && $2==s' "$last" >"$FROZEN/$name.txt.new"
    if [ ! -s "$FROZEN/$name.txt.new" ]; then
        rm -f "$FROZEN/$name.txt.new"
        return 1
    fi
    mv "$FROZEN/$name.txt.new" "$FROZEN/$name.txt"
    tmux kill-session -t "=$name"
}

thaw() {
    local name=$1
    local f=$FROZEN/$name.txt
    local first=1 _ widx wname wact layout wid pidx path pact cmd
    local active_win=

    while IFS=$US read -r _ _ widx wname wact _ layout _; do
        wname=${wname#:}
        local paths=() cmds=() actives=() pidxs=()
        while IFS=$US read -r _ _ _ _ _ pidx _ path pact cmd _; do
            pidxs+=("$pidx") paths+=("${path#:}") actives+=("$pact") cmds+=("$cmd")
        done < <(awk -F'\t' -v OFS="$US" -v w="$widx" '$1=="pane" && $3==w { $1=$1; print }' "$f")
        [ "${#paths[@]}" -gt 0 ] || continue

        if [ "$first" = 1 ]; then
            wid=$(tmux new-session -dP -F '#{window_id}' -s "$name" -n "$wname" -c "${paths[0]}")
            first=0
        else
            wid=$(tmux new-window -dP -F '#{window_id}' -t "=$name:" -n "$wname" -c "${paths[0]}")
        fi
        local i
        for ((i = 1; i < ${#paths[@]}; i++)); do
            tmux split-window -d -t "$wid" -c "${paths[i]}"
        done
        tmux select-layout -t "$wid" "$layout" 2>/dev/null || true

        # panes come back in index order; relaunch the programs resurrect is set up for
        local panes
        mapfile -t panes < <(tmux list-panes -t "$wid" -F '#{pane_id}')
        for ((i = 0; i < ${#panes[@]}; i++)); do
            case "${cmds[i]:-}" in
                nvim | lazygit) tmux send-keys -t "${panes[i]}" "${cmds[i]}" Enter ;;
            esac
            [ "${actives[i]:-}" = 1 ] && tmux select-pane -t "${panes[i]}"
        done
        [ "$wact" = 1 ] && active_win=$wid
    done < <(awk -F'\t' -v OFS="$US" '$1=="window" { $1=$1; print }' "$f")

    [ -n "$active_win" ] && tmux select-window -t "$active_win"
    rm -f "$f"
}

# subcommand args: TYPE SESSION TARGET (type is S/W/P, or FS/FW/FP if frozen)
case "${1:-}" in
    --list) list; exit ;;
    # rebuild a frozen session without opening the picker (quickshell's hub)
    --thaw) if [ -f "$FROZEN/$2.txt" ] && ! tmux has-session -t "=$2" 2>/dev/null; then thaw "$2"; fi; exit ;;
    --freeze) case "$2" in S | W | P) freeze "$3" || true ;; esac; exit ;;
    --kill)
        case "$2" in
            S) leave "$3" && tmux kill-session -t "$4" ;;
            W) tmux kill-window -t "$4" ;;
            P) tmux kill-pane -t "$4" ;;
            F?) rm -f "$FROZEN/$3.txt" ;;
        esac
        exit ;;
    --rename)
        case "$2" in
            S) cur=$3 what=session ;;
            W) cur=$(tmux display -p -t "$4" '#{window_name}') what=window ;;
            P) cur=$(tmux display -p -t "$4" '#{pane_title}') what=pane ;;
            FS) cur=$3 what="frozen session" ;;
            FW) cur=$(awk -F'\t' -v w="${4##*:}" '$1=="window" && $3==w { sub(/^:/, "", $4); print $4 }' "$FROZEN/$3.txt") what="frozen window" ;;
            *) exit 0 ;;
        esac
        printf '\n'
        read -r -e -i "$cur" -p "  $(fg "$C_ACID")rename $what:$(printf '\033[0m') " new </dev/tty || exit 0
        [ -n "$new" ] && [ "$new" != "$cur" ] || exit 0
        case "$2" in
            S | FS)
                new=$(tr '.:' '__' <<<"$new")   # tmux target syntax reserves both
                if tmux has-session -t "=$new" 2>/dev/null || [ -e "$FROZEN/$new.txt" ]; then
                    printf '  exists already, press a key'; read -rsn1 </dev/tty; exit 0
                fi
                if [ "$2" = S ]; then tmux rename-session -t "$4" "$new"; else mv "$FROZEN/$3.txt" "$FROZEN/$new.txt"; fi ;;
            W) tmux rename-window -t "$4" "$new" ;;
            P) tmux select-pane -t "$4" -T "$new" ;;
            FW) awk -F'\t' -v OFS='\t' -v w="${4##*:}" -v n="$new" '$1=="window" && $3==w { $4 = ":" n } { print }' "$FROZEN/$3.txt" >"$FROZEN/$3.txt.new" && mv "$FROZEN/$3.txt.new" "$FROZEN/$3.txt" ;;
        esac
        exit 0 ;;
    --confirm-kill)
        case "$2" in
            S) what="session ${3}" ;;
            W) what="window ${4#=}" ;;
            P) what="pane ${4#=}" ;;
            *) what="the frozen snapshot of ${3}" ;;
        esac
        printf '\n  %s\033[1mkill %s?\033[0m  %sy\033[0m%s kill · any other key cancels\033[0m ' \
            "$(fg "$(color red '#e8606e')")" "$what" "$(fg "$C_ACID")" "$(fg "$C_GRAY")"
        read -rsn1 k </dev/tty
        [ "$k" = y ] && "${BASH_SOURCE[0]}" --kill "$2" "$3" "$4"
        exit 0 ;;
    --preview)
        case "$2" in
            S) tmux capture-pane -ep -t "$4:" ;;
            W | P) tmux capture-pane -ep -t "$4" ;;
            *)
                awk -F'\t' '$1=="window" { sub(/^:/, "", $4); print "  " $3 ": " $4 }' "$FROZEN/$3.txt"
                echo
                awk -F'\t' '$1=="pane" { sub(/^:/, "", $8); print "  " $3 "." $6 "  " $10 "  " $8 }' "$FROZEN/$3.txt" ;;
        esac
        exit ;;
esac

# keybind bar: keys in the accent color, labels dimmed
key() { printf '%s\033[1m%s\033[0m%s %s\033[0m' "$(fg "$C_ACID")" "$1" "$(fg "$C_GRAY")" "$2"; }
sep="$(fg "$C_DIM")  │  "$'\033[0m'
footer="$(key enter jump)$sep$(key ^f freeze)$sep$(key ^r rename)$sep$(key ^x kill)$sep$(key ^n new)"

colors="fg+:$C_FG,bg+:$C_SURFACE,hl:$C_NEON,hl+:$C_ACID,pointer:$C_ACID,prompt:$C_ACID"
colors+=",input-border:$C_DIM,preview-border:$C_DIM,label:$C_GRAY,footer:$C_GRAY"

# fields: {1} tree label, {2} type, {3} session, {4} target
out=$(list | fzf \
    --delimiter='\t' --with-nth=1 --nth=1 \
    --layout=reverse --height=100% --border=none --no-scrollbar --padding=1,2 \
    --info=inline-right --prompt='❯ ' --pointer='▌' --ellipsis='…' \
    --input-border=rounded --input-label=' filter · ^n creates (or prompts) ' \
    --list-border=none \
    --color="$colors" \
    --ansi --footer="$footer" --footer-border=none \
    --preview="$0 --preview {2} {3} {4}" \
    --preview-window='right,55%,rounded,noinfo' --preview-label=' preview ' \
    --bind="ctrl-f:execute-silent($0 --freeze {2} {3})+reload($0 --list)" \
    --bind="ctrl-r:execute($0 --rename {2} {3} {4})+reload($0 --list)" \
    --bind="ctrl-x:execute($0 --confirm-kill {2} {3} {4})+reload($0 --list)" \
    --print-query --expect=ctrl-n) || true

query=$(sed -n 1p <<<"$out")
key=$(sed -n 2p <<<"$out")
sel=$(sed -n 3p <<<"$out")

if [ "$key" = ctrl-n ]; then
    # no query typed: ask for the name instead of silently doing nothing
    if [ -z "$query" ]; then
        read -r -e -p "  $(fg "$C_ACID")new session:$(printf '\033[0m') " query </dev/tty || exit 0
    fi
    [ -n "$query" ] || exit 0
    name=$(tr '.:' '__' <<<"$query")
    tmux has-session -t "=$name" 2>/dev/null || tmux new-session -ds "$name" -c "$HOME"
    target="=$name"
elif [ -n "$sel" ]; then
    type=$(cut -f2 <<<"$sel")
    name=$(cut -f3 <<<"$sel")
    target=$(cut -f4 <<<"$sel")
    if [[ $type == F* ]]; then
        tmux has-session -t "=$name" 2>/dev/null || thaw "$name"
    fi
else
    exit 0
fi

# window/pane rows: land on that window (and pane) inside the session
case "$target" in
    *.*) tmux select-window -t "${target%.*}" && tmux select-pane -t "$target" ;;
    *:*) tmux select-window -t "$target" ;;
esac
tmux switch-client -t "=$name"
