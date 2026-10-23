# tmux-sessionizer

Popup tree of sessions → windows → panes, with fzf filtering and a live
preview. Sessions can be **frozen** (snapshot + kill, kept as `❄` rows) and
thawed later; snapshots are cut from tmux-resurrect's save, so it needs
`tmux-plugins/tmux-resurrect` installed alongside.

Keys inside the popup: `enter` jump (thaws frozen), `^f` freeze session,
`^r` rename the selected session / window / pane (frozen sessions and windows too),
`^x` kill node / discard frozen (asks `y` first), `^n` new session named by the query.

Colors come from `@color-*` tmux options (`fg neon acid dim gray surface`),
with built-in fallbacks.

## Use

```tmux
run '~/.config/tmux/plugins/tmux-sessionizer/sessionizer.tmux'   # or: set -g @plugin 'you/tmux-sessionizer'
bind -T vim-normal s sessionizer
```

It registers a `sessionizer` command alias and binds nothing itself.
Requires fzf ≥ 0.5x (`--footer`, `--input-border`).
