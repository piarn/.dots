#!/usr/bin/env bash
# Bootstraps this dotfiles repo onto a machine via GNU Stow.
#
#   ./install.sh [terminal|desktop]   install (default: this machine's saved
#                                     profile, else terminal)
#   ./install.sh --doctor             read-only health check
#   ./install.sh --outdated           pinned release tools behind upstream
#   ./install.sh --ci                 package/download steps only (CI containers)
#
# terminal: shell, editor, tmux, git and the TUI tools — everything in this
#   repo. For machines that only need a terminal (a work laptop, a server).
# desktop:  terminal, then ~/.rice/install.sh on top: sway, quickshell, the
#   GUI apps and the session services.
# The profile is remembered in ~/.config/dots/profile, so a plain re-run
# keeps it; naming the other one switches (desktop -> terminal unlinks the
# desktop configs, it doesn't uninstall packages).
set -euo pipefail

DOTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$DOTS_DIR/.bootstrap"
# shellcheck source=.bootstrap/lib.sh
. "$BOOTSTRAP_DIR/lib.sh"

PACKAGES=(agent-pool bash bat fd fish git lazydocker lazygit nvim ripgrep scripts ssh tmux yazi)
# Fetched over https so a fresh machine needs no ssh key to install;
# pushes still go over ssh.
RICE_REPO="https://github.com/piarn/.rice.git"
RICE_PUSH_URL="git@github.com:piarn/.rice.git"

# shellcheck disable=SC2034  # read by .bootstrap/lib.sh
declare -A RELEASE_VERSIONS=(
    [yazi]=v26.9.1
    [lazygit]=v0.65.1
    [lazydocker]=v0.25.2
    [mise]=v2026.9.18
    [tree-sitter]=v0.27.0
)
# shellcheck disable=SC2034
declare -A RELEASE_REPOS=(
    [yazi]=sxyazi/yazi
    [lazygit]=jesseduffield/lazygit
    [lazydocker]=jesseduffield/lazydocker
    [mise]=jdx/mise
    [tree-sitter]=tree-sitter/tree-sitter
)
RELEASE_TOOLS=(yazi lazygit lazydocker mise tree-sitter)

# Several Mason-managed LSP servers (json-lsp, bash-language-server,
# yaml-language-server, ...) are npm packages, so npm must exist before
# nvim can install them.
install_node() {
    command -v npm >/dev/null 2>&1 && return
    case "$(package_manager)" in
        apt) sudo apt update && sudo apt install -y nodejs npm ;;
        dnf) sudo dnf install -y nodejs npm ;;
        pacman) sudo pacman -S --needed --noconfirm nodejs npm ;;
        *) echo "warning: npm not found and no supported package manager (apt/dnf/pacman) detected;" >&2
           echo "         npm-based LSP servers will fail to install until it's on PATH" >&2 ;;
    esac
}

# Installs the Mason packages declared in nvim/.config/nvim/lua/plugins/lsp.lua's
# ensure_installed (as mason package names, which differ from the lspconfig
# server names used there), so the first interactive launch isn't stuck
# waiting on installs. Only installs what's actually missing, so this is
# fast and safe to re-run any time (e.g. after adding a language above).
MASON_PACKAGES=(
    gopls
    basedpyright
    ruff
    lua-language-server
    clangd
    bash-language-server
    yaml-language-server
    json-lsp
    rust-analyzer
    nimlangserver
)

install_lsp_servers() {
    command -v nvim >/dev/null 2>&1 || return 0

    local missing=() pkg
    for pkg in "${MASON_PACKAGES[@]}"; do
        if ! nvim --headless -c "lua if require('mason-registry').is_installed('$pkg') then os.exit(0) else os.exit(1) end" 2>/dev/null; then
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        echo "==> LSP servers already installed, nothing to do"
        return
    fi

    echo "==> installing LSP servers via Mason: ${missing[*]}"
    local pkg_list
    pkg_list=$(printf "'%s'," "${missing[@]}")
    nvim --headless "+MasonInstall ${missing[*]}" \
        "+lua vim.wait(180000, function() local r = require('mason-registry'); for _, n in ipairs({${pkg_list}}) do if not r.is_installed(n) then return false end end; return true end, 500)" \
        +qa 2>&1 | grep -Ev '^\[[a-zA-Z0-9._-]+\] +(log|fetch|status|checkout)' || true
}

# Keep .rice in step with .dots: fast-forward only, and a failure (local
# edits in the way, diverged history, offline) never blocks the install.
# A local branch with no upstream (an experiment) is left alone entirely.
update_rice() {
    local branch
    branch=$(git -C "$RICE_DIR" branch --show-current)
    if ! git -C "$RICE_DIR" rev-parse -q --verify '@{upstream}' >/dev/null 2>&1; then
        echo "==> .rice is on ${branch:-a detached HEAD} with no upstream; not updating it"
        return
    fi
    echo "==> updating .rice ($branch)"
    git -C "$RICE_DIR" pull --ff-only \
        || echo "warning: couldn't fast-forward $RICE_DIR; continuing with what's there" >&2
}

# .rice owns the palette every config here takes its colors from (tmux,
# nvim, fish, fzf, eza, yazi, lazygit, lazydocker), and on the desktop
# profile the desktop itself. Both profiles clone it and render the current
# theme; only desktop installs anything from it (~/.rice/install.sh).
install_rice() {
    if [ ! -d "$RICE_DIR/.git" ]; then
        echo "==> cloning .rice"
        git clone "$RICE_REPO" "$RICE_DIR"
        git -C "$RICE_DIR" remote set-url --push origin "$RICE_PUSH_URL"
    else
        update_rice
    fi
    # everything gets reloaded once, at the end of the install
    DOTS_NO_RELOAD=1 "$RICE_DIR/bin/apply-theme"
}

install_yazi() { install_from_github_release yazi "${YAZI_ARCH:+${YAZI_ARCH}.zip}" yazi ya; }
install_lazygit() { install_from_github_release lazygit "${RELEASE_ARCH:+linux_${RELEASE_ARCH}.tar.gz}" lazygit; }
install_lazydocker() { install_from_github_release lazydocker "${RELEASE_ARCH:+Linux_${RELEASE_ARCH}.tar.gz}" lazydocker; }
# mise: per-project language toolchains, activated by fish/conf.d/mise.fish.
# The asset pattern matches just the glibc tarball (not -musl, .tar.zst or .sig).
install_mise() { install_from_github_release mise "${MISE_ARCH:+linux-${MISE_ARCH}.tar.gz}" mise; }
# The CLI nvim-treesitter's main branch builds parsers with (0.26.1+; Debian
# and Ubuntu package a far older one).
install_tree_sitter() { install_from_github_release tree-sitter "${TS_ARCH:+tree-sitter-cli-linux-$TS_ARCH.zip}" tree-sitter; }

install_tpm() {
    local tpm_dir="$HOME/.tmux/plugins/tpm"
    [ -d "$tpm_dir" ] || git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
}

# fisher.fish and bass's function files are committed under fish/.config/fish
# already (stow drops them straight in), so this is normally a no-op. It
# only does real work — via the scripts in .bootstrap/fish — the first time
# fish itself is set up on a machine, or if those tracked files are missing.
install_fish_plugins() {
    command -v fish >/dev/null 2>&1 || return 0
    fish -c 'type -q fisher' >/dev/null 2>&1 && return
    echo "==> bootstrapping fisher + plugins via .bootstrap/fish"
    fish -c "source $BOOTSTRAP_DIR/fish/install_fisher.sh"
    fish -c "source $BOOTSTRAP_DIR/fish/install_bass.sh"
}

# The session's one ssh-agent (ssh/.config/systemd/user/ssh-agent.service).
# Enabled rather than tied to the desktop session: it lives as long as the
# user manager, so loaded keys survive a sway restart.
enable_ssh_agent() {
    systemctl --user enable --now ssh-agent.service >/dev/null 2>&1 \
        || echo "warning: couldn't enable ssh-agent.service (no systemd user session?)" >&2
}

# Read-only preflight: verifies everything the install will need is
# obtainable *before* anything is installed, removed or modified. No sudo,
# no package-index refresh, no writes — it only inspects and reports, and
# aborts with the full list of problems if any are found.
preflight() {
    local problems=() name extra=()

    echo "==> preflight: checking dependencies (read-only)"
    [ -n "$(package_manager)" ] || problems+=("no supported package manager (apt/dnf/pacman)")

    # Only what can't be bootstrapped by the installer itself.
    for name in sudo git python3; do
        command -v "$name" >/dev/null 2>&1 || problems+=("'$name' is required to run the installer but is not on PATH")
    done
    [ -n "$RELEASE_ARCH" ] || problems+=("unsupported CPU architecture $(uname -m) (yazi/lazygit/lazydocker release binaries)")

    command -v npm >/dev/null 2>&1 || extra+=(nodejs npm)
    if [ "$(package_manager)" = apt ] && ! python3 -c 'import venv, ensurepip' >/dev/null 2>&1; then
        extra+=(python3-venv)
    fi
    mapfile -t -O "${#problems[@]}" problems < <(preflight_packages "$BOOTSTRAP_DIR/packages.txt" "${extra[@]}")

    if command -v curl >/dev/null 2>&1; then
        curl -fsS --head --max-time 10 https://github.com >/dev/null 2>&1 \
            || problems+=("cannot reach https://github.com")
    fi
    if [ ! -d "$RICE_DIR/.git" ] && [ "$MODE" != ci ]; then
        GIT_TERMINAL_PROMPT=0 git ls-remote "$RICE_REPO" HEAD >/dev/null 2>&1 \
            || problems+=("cannot read $RICE_REPO")
    fi

    if [ ${#problems[@]} -gt 0 ]; then
        echo "error: preflight failed, nothing was changed:" >&2
        printf '  - %s\n' "${problems[@]}" >&2
        exit 1
    fi
    echo "==> preflight OK"
}

# Read-only health check (`./install.sh --doctor`): what install.sh would
# still change, plus what can break quietly after it ran. On the desktop
# profile it goes on to ~/.rice/install.sh --doctor. Exits 1 on a failure.
doctor() {
    local name missing=() profile
    profile=$(saved_profile)
    doctor_init
    echo "profile: $profile"

    echo "packages"
    mapfile -t missing < <(missing_packages "$BOOTSTRAP_DIR/packages.txt")
    if [ ${#missing[@]} -eq 0 ]; then ok "packages.txt"; else bad "not installed: ${missing[*]}"; fi
    doctor_releases ok bad "${RELEASE_TOOLS[@]}"

    echo "links"
    local entries=() fails_before=$DOCTOR_FAILS
    for name in "${PACKAGES[@]}"; do entries+=("$DOTS_DIR:$name"); done
    while IFS= read -r name; do
        [ -d "$DOTS_DIR/extras/$name/home" ] && entries+=("$DOTS_DIR/extras/$name:home")
    done < <(grep -v '^\s*$' "$DOTS_DIR/.extras-enabled" 2>/dev/null)
    doctor_links ok bad "${entries[@]}" || true
    local dangling
    dangling=$(dangling_links)
    if [ -n "$dangling" ]; then
        bad "dangling links into ~/.dots or ~/.rice (install.sh removes them):"
        sed 's/^/          /' <<<"$dangling"
    fi
    [ "$DOCTOR_FAILS" -gt "$fails_before" ] || ok "every package and enabled extra is linked"

    echo "rice"
    if [ -d "$RICE_DIR/.git" ]; then ok "$RICE_DIR"; else bad "$RICE_DIR not cloned (the palette every config reads)"; fi

    echo "agent pool"
    if [ -x "$HOME/.agent-pool/bin/agent-pool" ]; then
        local pool_status
        pool_status=$("$HOME/.agent-pool/bin/agent-pool" status 2>&1 || true)
        while IFS= read -r name; do
            case "$name" in
                *"not logged in"*) warn "${name#??}" ;;
                *) ok "${name#??}" ;;
            esac
        done <<<"$pool_status"
        case "$(command -v claude 2>/dev/null)" in
            "$HOME/.agent-pool/bin/claude") ok "claude on PATH is the pool's" ;;
            "") warn "claude isn't installed" ;;
            *) bad "claude on PATH is $(command -v claude), not ~/.agent-pool/bin/claude (open a new shell)" ;;
        esac
    else
        bad "agent pool not linked (run install.sh)"
    fi

    echo "services"
    if systemctl --user -q is-active ssh-agent.service; then
        ok "ssh-agent.service"
        [ "${SSH_AUTH_SOCK:-}" = "${XDG_RUNTIME_DIR:-}/ssh-agent.socket" ] || [ -n "${SSH_CONNECTION:-}" ] \
            || warn "this shell's SSH_AUTH_SOCK isn't the session agent (${SSH_AUTH_SOCK:-unset}); log out and back in"
    else
        bad "ssh-agent.service not running (systemctl --user enable --now ssh-agent.service)"
    fi

    # Configs change on disk long before the processes using them restart
    # (a tmux server kept alive by resurrect/continuum can outlive weeks
    # of commits), so compare what's loaded against what's there.
    echo "running configs"
    local loaded newest
    if tmux list-sessions >/dev/null 2>&1; then
        loaded=$(tmux show -gqv @dots-loaded)
        newest=$(stat -L -c %Y "$HOME/.config/tmux/tmux.conf" "$RICE_DIR/tmux/theme.conf" \
            "$DOTS_DIR"/tmux/.config/tmux/plugins/*/*.tmux 2>/dev/null | sort -n | tail -1)
        if [ -z "$loaded" ]; then
            bad "tmux server predates tmux.conf's load marker, so its config is likely stale (run dots-reload)"
        elif [ "${newest:-0}" -gt "$loaded" ]; then
            bad "tmux is running a tmux.conf/theme older than the one on disk (run dots-reload)"
        else
            ok "tmux config current"
        fi
    else
        ok "no tmux server running"
    fi

    echo "repos"
    if [ -n "$(git -C "$DOTS_DIR" status --porcelain 2>/dev/null)" ]; then
        warn "$DOTS_DIR has uncommitted changes"
    else
        ok "$DOTS_DIR clean"
    fi

    local fails=$DOCTOR_FAILS warns=$DOCTOR_WARNS
    if [ "$profile" = desktop ]; then
        echo
        if [ -x "$RICE_DIR/install.sh" ]; then
            "$RICE_DIR/install.sh" --doctor || fails=$((fails + 1))
        else
            echo "  FAIL  $RICE_DIR/install.sh missing (desktop profile)"
            fails=$((fails + 1))
        fi
        return $(( fails > 0 ))
    fi
    echo
    if [ "$fails" -gt 0 ]; then
        echo "$fails problem(s), $warns warning(s)"
        return 1
    fi
    echo "all good ($warns warning(s))"
}

# --ci (.github/workflows/install.yml, as root in a fresh distro
# container): everything that installs from a package manager or a
# download, so a renamed/dropped package fails there first.
ci() {
    preflight
    install_packages "$BOOTSTRAP_DIR/packages.txt"
    install_node
    install_yazi
    install_lazygit
    install_lazydocker
    install_mise
    install_tree_sitter
}

MODE=install
profile=""
case "${1:-}" in
    --doctor) doctor; exit ;;
    --outdated) outdated_releases "${RELEASE_TOOLS[@]}"; exit ;;
    --ci) MODE=ci; ci; exit ;;
    terminal|desktop) profile=$1 ;;
    '') profile=$(saved_profile) ;;
    *) sed -n '4,8p' "$0" | sed 's/^# \{0,1\}/usage: /' >&2; exit 1 ;;
esac
previous=$(saved_profile)
echo "==> profile: $profile"

preflight
install_packages "$BOOTSTRAP_DIR/packages.txt"
install_node
install_rice
install_yazi
install_lazygit
install_lazydocker
install_mise
install_tree_sitter

stow_packages "$DOTS_DIR" "${PACKAGES[@]}"
save_profile "$profile"
# Opt-in extras (extras/extras.sh) stay out of PACKAGES; this only re-links
# the ones already enabled on this machine, so new files in them land too.
"$DOTS_DIR/extras/extras.sh" restow
prune_dangling_links

reload_user_units
enable_ssh_agent
install_fish_plugins
install_tpm
"$HOME/.tmux/plugins/tpm/bin/install_plugins" >/dev/null 2>&1 || true
"$HOME/.agent-pool/bin/agent-pool" setup

if [ "$profile" = desktop ]; then
    "$RICE_DIR/install.sh"
elif [ "$previous" = desktop ] && [ -x "$RICE_DIR/install.sh" ]; then
    "$RICE_DIR/install.sh" --uninstall
fi

# Long-lived processes (tmux server, and on desktop sway, quickshell,
# kitty) read their config once at startup; push what was just linked in.
"$DOTS_DIR/scripts/.local/bin/dots-reload"

install_lsp_servers

echo
if [ -d "$BACKUP_DIR" ]; then
    echo "Done ($profile). Files that were in the way of a link were moved to $BACKUP_DIR"
else
    echo "Done ($profile)."
fi
