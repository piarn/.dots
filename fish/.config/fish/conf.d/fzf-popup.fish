# fzf.fish's pickers (Ctrl+R history, Ctrl+Alt+F files, git log/status,
# processes, variables) open as a tmux popup over the pane when in tmux;
# outside tmux fzf ignores --tmux and draws in the terminal as before.
# Only these: nvim's fzf-lua runs fzf inside nvim and must not get it.
for picker in history directory git_log git_status processes variables
    set -g fzf_{$picker}_opts --tmux=center,80%,70%
end
