# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]; then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
# the agent pool's `claude` wraps the real one in ~/.local/bin
case ":$PATH:" in *":$HOME/.agent-pool/bin:"*) ;; *) PATH="$HOME/.agent-pool/bin:$PATH" ;; esac
export PATH

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions
if [ -d ~/.bashrc.d ]; then
    for rc in ~/.bashrc.d/*; do
        if [ -f "$rc" ]; then
            . "$rc"
        fi
    done
fi
unset rc

# tmux NAME...: create a session per name (existing ones are reused) and attach
# to the first. Bare `tmux` prints usage; real tmux subcommands/flags pass through.
tmux() {
    if [ $# -eq 0 ]; then
        echo "usage: tmux NAME [NAME...]   create/attach named sessions (first is attached)"
        echo "       tmux <tmux-command|-flag> ...   passed to tmux as usual"
        return 1
    fi
    case $1 in
        -*) command tmux "$@"; return ;;
    esac
    if command tmux list-commands -F '#{command_list_name} #{command_list_alias}' 2>/dev/null | tr ' ' '\n' | grep -qxF -- "$1"; then
        command tmux "$@"; return
    fi
    local n first=$1
    for n in "$@"; do
        n=${n//[.:]/_}
        command tmux has-session -t "=$n" 2>/dev/null || command tmux new-session -d -s "$n" || return
    done
    first=${first//[.:]/_}
    if [ -n "$TMUX" ]; then
        command tmux switch-client -t "=$first"
    else
        command tmux attach-session -t "=$first"
    fi
}
