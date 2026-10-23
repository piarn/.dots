# Toolchain locations: the list in ~/.config/environment.d/10-langs.conf,
# the same one the desktop session gets. Before mise.fish, which needs
# MISE_DATA_DIR.
set -l conf ~/.config/environment.d/10-langs.conf
test -f $conf; or return
for line in (string match -rv '^\s*(#|$)' <$conf)
    set -l kv (string split -m1 = -- $line)
    set -l val (string replace -a '${HOME}' $HOME -- $kv[2])
    if test $kv[1] = PATH
        # entries before ${PATH} go first, the ones after it last
        set -l parts (string split '${PATH}' -- $val)
        fish_add_path --global --move --path (string split : -- $parts[1] | string match -rv '^$')
        set -q parts[2]; and fish_add_path --global --append --path (string split : -- $parts[2] | string match -rv '^$')
    else
        set -gx $kv[1] $val
    end
end
