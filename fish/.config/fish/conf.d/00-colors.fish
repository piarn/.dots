# Colors: the one fixed palette (black, dark and light grays; muted
# status colors for errors/diffs).

# prompt
set -g color_dir bdbdbd

# eza (its theme is ~/.config/eza/theme.yml)

# eza applies LS_COLORS then EZA_COLORS *after* theme.yml, so these reclaim
# the ten classic file-kind codes from whatever LS_COLORS this system
# already exports (dircolors) — matches ~/.config/eza/theme.yml's filekinds.
set -gx EZA_COLORS "di=1;38;2;189;189;189:ln=3;38;2;127;168;163:ex=1;38;2;230;230;230:pi=38;2;194;160;97:so=38;2;160;138;173:bd=1;38;2;127;147;173:cd=1;38;2;127;147;173:or=1;38;2;196;106;106"

# fzf
set -gx FZF_DEFAULT_OPTS '--cycle --layout=reverse --border --height=90% --preview-window=wrap --marker="*" --color=fg:#d0d0d0,bg:#0b0b0b,hl:#bdbdbd,fg+:#0b0b0b,bg+:#2c2c2c,hl+:#e6e6e6,info:#e6e6e6,border:#2c2c2c,prompt:#bdbdbd,pointer:#bdbdbd,marker:#e6e6e6,spinner:#bdbdbd,header:#5f5f5f,gutter:#0b0b0b'
