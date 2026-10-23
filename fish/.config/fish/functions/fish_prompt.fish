function fish_prompt
    # Directory (shortened) — everything else (git branch, ...) lives in the
    # tmux status bar instead.
    set_color $color_dir
    echo -n (prompt_pwd)
    set_color normal
    echo -n ' $ '
end
