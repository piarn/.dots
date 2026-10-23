# tmux

`tmux/.config/tmux/tmux.conf` plus two local plugins, stowed to
`~/.config/tmux/`. Prefix is `Space`; [`vim-modes`](.config/tmux/plugins/vim-modes/README.md)
gives NORMAL / INSERT / VISUAL modes on top.

## Layout

| Path | What |
| --- | --- |
| `tmux.conf` | options, TPM plugins, persistence, **all direct (Alt) binds** |
| `scripts/confirm-kill.sh` | the kill-confirm popup for panes/windows |
| `scripts/open-url.sh` | Ctrl+click URL opener |
| `plugins/vim-modes/` | modal keys and the leader (prefix) table — see its README |
| `plugins/tmux-sessionizer/` | session → window → pane tree popup, freeze/thaw — see its README |

TPM plugins (`tmux-plugins/*`) are cloned to `~/.config/tmux/plugins/` by
`prefix I`; the two local ones are committed here and only symlinked. Because
stow chokes on this repo's other packages, the per-file symlinks under
`~/.config/tmux/plugins/<plugin>/` are the ones stow would make — a new file in
a plugin needs its symlink too (`ln -s` the same relative path as its siblings).

Load order in `tmux.conf` matters:

1. options, `theme.conf` (colors)
2. TPM plugins + `run tpm`
3. `vim-modes` — after TPM so its copy-mode keys beat tmux-yank's
4. `tmux-sessionizer` and the direct binds — after vim-modes, because each
   bind's NORMAL-mode copy ends in `vim-modes-return`, an alias vim-modes defines

## Sessions: one per case

- Each piece of work gets its own session; jump between them with the
  sessionizer (`Alt+s`), `Alt+S` for the
  previous one.
- **Persistence:** `tmux-resurrect` + `tmux-continuum` autosave every 10 min and
  restore on server start, so a reboot brings everything back running (pane
  contents captured; `nvim` is relaunched).
- **Frozen sessions** are the sessionizer's own layer on top: `^f` on a row
  snapshots that session's windows, panes, layouts and cwds to
  `~/.local/share/tmux/frozen/<name>.txt` and kills it. It shows as `❄` in the
  tree until you open it, which rebuilds it and deletes the snapshot. Use it to
  park a case without keeping it running.

### Sessionizer popup

```
❯ filter                                  │ preview of the selected node
● project-a  3 win · attached             │
  ├─ 1: editor  (2p)                      │
  │  ├─ 1 nvim  ~/projects/a              │
  │  └─ 2 fish  ~/projects/a              │
  └─ 2: shell  (1p)                       │
❄ project-b  frozen 3h ago · 2 win        │
```

| Key | Action |
| --- | --- |
| `enter` | jump to session / window / pane (thaws a `❄` one first) |
| `^f` | freeze the session the row belongs to (refuses if it's your only session) |
| `^r` | rename the selected session / window / pane (frozen ones too; `.` and `:` become `_` in session names) |
| `^x` | kill the session / window / pane, or discard a frozen snapshot (asks `y` first) |
| `^n` | new session named by what you typed in the filter |
| type | fuzzy filter over every row, panes included (`nvim` finds every nvim pane) |

Colors come from the `@color-*` tmux options in `theme.conf` (border, tree,
key bar, fzf).

## Direct binds

No prefix needed, but only in **NORMAL** and **VISUAL** mode (bound in the
`vim-normal` and `copy-mode-vi` key tables). **INSERT has none**, so programs in
the pane get their Alt keys untouched; press `Escape` first to use them. They
mix browser tab keys (Firefox/Chrome) with zellij's Alt layer; `hjkl` stays vim.

**Windows — browser tabs**

| Key | Action |
| --- | --- |
| `Alt+1` … `Alt+8` | window 1–8 |
| `Alt+9` | last window (as in browsers) |
| `Alt+,` / `Alt+.` | previous / next window |
| `Alt+Tab` | last-used window |
| `Alt+t` | new window (current directory) |
| `Alt+r` | rename window |
| `Alt+Shift+w` | close window (confirm popup, window tinted red) |
| `Alt+i` / `Alt+o` | move window left / right (zellij) |

**Panes — zellij**

| Key | Action |
| --- | --- |
| `Alt+h/j/k/l` | focus pane |
| `Alt+n` | new pane on the roomier axis (right if wide, else below) |
| `Alt+\` / `Alt+-` | split right / below (current directory) |
| `Alt+w` | close pane (confirm popup, pane tinted red) |
| `Alt+f` | zoom / unzoom |
| `Alt+Shift+h/j/k/l` | resize by 5 |

**Sessions**

| Key | Action |
| --- | --- |
| `Alt+s` | sessionizer popup |
| `Alt+Shift+s` | previous session |

Killing asks first: a small popup names the pane/window and tints it red until
you answer (`y` kills, any other key cancels; `scripts/confirm-kill.sh`). The
tint is cleared either way. The sessionizer's `^x` asks the same way.

Notes:

- In INSERT nothing here fires, and in NORMAL/VISUAL tmux takes the keys, so
  Neovim never sees them there. `Ctrl+h/j/k/l` (vim-tmux-navigator) is the
  Neovim-aware way to cross splits and works in INSERT.
- `Alt+[` / `Alt+]` are deliberately unused: that's the escape-sequence prefix
  and unreliable in tmux. Your terminal or sway may also grab `Alt+Tab` before
  tmux sees it.
- To change one, edit its line in the *Direct chords* block at the bottom of
  `tmux.conf`: each chord has a `vim-normal` line (ends in `; vim-modes-return`)
  and a `copy-mode-vi` line.

## Mouse: Ctrl+click opens URLs

`Ctrl+click` on a URL opens it, in any mode: an OSC 8 hyperlink, or a plain-text
`http(s)://`, `ftp://` or `file://` URL found in the clicked row (trailing
punctuation and unbalanced brackets are trimmed). It opens through
`~/.local/bin/browser` (the machine-local Firefox launcher: snap, flatpak or
native) and falls back to `xdg-open`. A plain click stays with tmux
(focus/selection); a terminal's own link click doesn't reach a program that has
the mouse, which is why this lives in tmux. A URL wrapped across two rows only
matches on the row you click.

## Leader (NORMAL mode) keys

Only vim-modes' own keys; window/pane/session management is the Alt layer above.

| Key | Action |
| --- | --- |
| `Space` then `h/j/k/l` | focus pane (hands over to vim splits) |
| `H/J/K/L` | resize |
| `i`, `v`, `Escape` | INSERT, VISUAL, back to NORMAL |
| `d`, `r` | detach, reload config |

tmux's stock leader keys for windows/panes/splits (`c n p l w x & z , s % " 0-9`)
are unbound in `tmux.conf`; other stock keys (`[`, `?`, `t`, …) still work.

## Reloading

`prefix r` (NORMAL: `Space r`) re-sources `tmux.conf`. The sessionizer plugin
re-registers its alias on reload (fixed alias slot, so nothing piles up).
