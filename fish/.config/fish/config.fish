if status is-interactive
    set -g fish_greeting
    # Interactive-only so scripts/plugins using fish `eval` are unaffected
    abbr -a --position command eval bass
end

fish_add_path ~/.local/bin
fish_add_path ~/bin
fish_add_path ~/.langs/go/bin
fish_add_path ~/.langs/flutter/bin

if test -f ~/.config/fish/local.fish
    source ~/.config/fish/local.fish
end

# Last, so it stays ahead of ~/.local/bin: the agent pool's `claude`
# (~/.agent-pool/bin/claude) wraps the real one (agent-pool/README.md).
fish_add_path --global --move --path ~/.agent-pool/bin
