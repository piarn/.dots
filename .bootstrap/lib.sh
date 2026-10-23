# shellcheck shell=bash
# Shared by ~/.dots/install.sh (the terminal profile) and ~/.rice/install.sh
# (the desktop layer on top of it): package lists, GitHub-release binaries,
# stow with conflict backup, and the profile this machine was installed as.
# Sourced, never run; expects `set -euo pipefail` from the caller.

DOTS_DIR="${DOTS_DIR:-$HOME/.dots}"
RICE_DIR="${RICE_DIR:-$HOME/.rice}"
LOCAL_BIN="$HOME/.local/bin"

# Which profile this machine runs: "terminal" (shell, editor, tmux and the
# TUI tools; e.g. a work laptop) or "desktop" (terminal plus sway,
# quickshell and the GUI apps from ~/.rice). install.sh writes it;
# extras.sh and --doctor read it.
PROFILE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dots/profile"

saved_profile() {
    local p
    p=$(cat "$PROFILE_FILE" 2>/dev/null || true)
    case "$p" in terminal|desktop) echo "$p" ;; *) echo terminal ;; esac
}

save_profile() {
    mkdir -p "$(dirname "$PROFILE_FILE")"
    echo "$1" >"$PROFILE_FILE"
}

# A few packages install a binary whose name doesn't match the package
# name, so a plain `command -v <package>` never finds them and they'd get
# re-installed (harmlessly, but noisily prompting for sudo) on every run.
declare -A PACKAGE_BIN_OVERRIDES=(
    [fd-find]=fd               # Fedora: package fd-find installs binary fd (Debian/Ubuntu: fdfind — see below)
    [wl-clipboard]=wl-copy
    [pulseaudio-utils]=pactl
    [ripgrep]=rg
    [neovim]=nvim
    [git-delta]=delta
    [ShellCheck]=shellcheck
)

# apt sometimes uses a differently-cased/named package than dnf's
# packages.txt name — add an entry here when that happens.
declare -A APT_NAME_OVERRIDES=(
    [ShellCheck]=shellcheck
)

# Same idea for pacman — Arch mostly matches dnf's naming (it's the
# outlier that needs translating, not the rule), so this only needs
# entries for the packages that actually differ.
declare -A ARCH_NAME_OVERRIDES=(
    [fd-find]=fd              # Arch just calls it fd, no split like Fedora/Debian
    [pulseaudio-utils]=libpulse   # pactl ships in libpulse, pulled in either by pipewire-pulse or pulseaudio
    [ShellCheck]=shellcheck
)

package_manager() {
    local name
    for name in apt dnf pacman; do
        command -v "$name" >/dev/null 2>&1 && { echo "$name"; return; }
    done
}

# Prints (one per line) the entries of packages file $1 (one binary/package
# name per line, dnf naming — see the override maps above for the handful
# that need translating on apt/pacman) not already on PATH.
missing_packages() {
    local pkg probe
    while IFS= read -r pkg; do
        pkg=${pkg%%#*}; pkg=${pkg//[[:space:]]/}
        [ -n "$pkg" ] || continue
        probe="${PACKAGE_BIN_OVERRIDES[$pkg]:-$pkg}"
        command -v "$probe" >/dev/null 2>&1 || echo "$pkg"
    done <"$1"
}

install_packages() {
    local pkg missing=()
    mapfile -t missing < <(missing_packages "$1")

    if [ ${#missing[@]} -eq 0 ]; then
        echo "==> packages already installed, nothing to do"
        return
    fi

    echo "==> installing packages: ${missing[*]}"
    case "$(package_manager)" in
        apt)
            local apt_pkgs=()
            for pkg in "${missing[@]}"; do apt_pkgs+=("${APT_NAME_OVERRIDES[$pkg]:-$pkg}"); done
            sudo apt update && sudo apt install -y "${apt_pkgs[@]}" ;;
        dnf)
            sudo dnf install -y "${missing[@]}" ;;
        pacman)
            local pacman_pkgs=()
            for pkg in "${missing[@]}"; do pacman_pkgs+=("${ARCH_NAME_OVERRIDES[$pkg]:-$pkg}"); done
            sudo pacman -S --needed --noconfirm "${pacman_pkgs[@]}" ;;
        *)
            echo "error: no supported package manager (apt/dnf/pacman) detected; install manually: ${missing[*]}" >&2
            exit 1 ;;
    esac
}

# preflight_packages <packages file>: one problem line per entry the
# configured repos can't provide. Read-only (no sudo, no index refresh).
# Extra package names to check can follow the file.
preflight_packages() {
    local file=$1 pm pkg name avail missing=()
    shift
    pm=$(package_manager)
    mapfile -t missing < <(missing_packages "$file")
    missing+=("$@")
    for pkg in "${missing[@]}"; do
        case "$pm" in
            apt)
                name="${APT_NAME_OVERRIDES[$pkg]:-$pkg}"
                avail=$(apt-cache policy "$name" 2>/dev/null | awk '/Candidate:/ {print $2}')
                [ -n "$avail" ] && [ "$avail" != "(none)" ] ;;
            dnf)
                # never let it ask anything: a repo whose signing key isn't
                # imported yet (the tailscale/netbird extras' repos) prompts
                # "Is this ok [y/N]", which sits there invisibly behind the
                # >/dev/null. Declining skips just that repo's key import;
                # the lookup still answers from the other repos.
                dnf -q --assumeno list --available "$pkg" </dev/null >/dev/null 2>&1 ;;
            pacman)
                name="${ARCH_NAME_OVERRIDES[$pkg]:-$pkg}"
                pacman -Si "$name" >/dev/null 2>&1 ;;
            *) true ;;
        esac || echo "package '$pkg' not available from $pm repos (if the index is stale, refresh it and retry)"
    done
}

case "$(uname -m)" in
    x86_64) RELEASE_ARCH=x86_64; YAZI_ARCH=x86_64-unknown-linux-gnu; MISE_ARCH=x64; TS_ARCH=x64 ;;
    aarch64) RELEASE_ARCH=arm64; YAZI_ARCH=aarch64-unknown-linux-gnu; MISE_ARCH=arm64; TS_ARCH=arm64 ;;
    *) RELEASE_ARCH=""; YAZI_ARCH=""; MISE_ARCH=""; TS_ARCH="" ;;
esac
export RELEASE_ARCH YAZI_ARCH MISE_ARCH TS_ARCH

# Release-binary tools aren't packaged for apt/dnf, so they come straight
# from each project's GitHub releases into ~/.local/bin, pinned so every
# machine (and CI) runs the same versions. Each installer declares its own
# in RELEASE_VERSIONS / RELEASE_REPOS (declare -A) before calling these.
# To upgrade one, bump its tag and re-run; --doctor flags a machine that's
# behind, --outdated one whose pin is. Newest tag:
#   curl -fsSL https://api.github.com/repos/<repo>/releases/latest | grep tag_name
RELEASE_VERSION_DIR="$HOME/.local/share/dots-release-versions"

# Whether ~/.local/bin/$1 is the pinned version: its marker says so, or
# (a copy installed before pinning, with no marker) its --version does.
release_current() {
    local version="${RELEASE_VERSIONS[$1]}"
    [ -x "$LOCAL_BIN/$1" ] || return 1
    [ "$(cat "$RELEASE_VERSION_DIR/$1" 2>/dev/null)" = "$version" ] && return 0
    [ ! -e "$RELEASE_VERSION_DIR/$1" ] && "$LOCAL_BIN/$1" --version 2>/dev/null | grep -qF "${version#v}"
}

# Installs $bin_name from its RELEASE_VERSIONS release of RELEASE_REPOS whose asset
# filename contains $asset_pattern: downloads it, extracts it (.tar.gz or
# .zip), and copies every binary named in $bin_names (may be more than
# one, e.g. yazi ships a "ya" companion binary) into ~/.local/bin. A no-op
# when that version is already installed, or when $bin_name was installed
# some other way (a distro package, `go install`, ...).
install_from_github_release() {
    local bin_name="$1" asset_pattern="$2"
    shift 2
    local repo="${RELEASE_REPOS[$bin_name]}"
    local bin_names=("$@")
    local version="${RELEASE_VERSIONS[$bin_name]}"
    local marker="$RELEASE_VERSION_DIR/$bin_name"

    if release_current "$bin_name"; then
        mkdir -p "$RELEASE_VERSION_DIR"
        echo "$version" >"$marker"
        return
    fi
    if [ ! -e "$LOCAL_BIN/$bin_name" ] && command -v "$bin_name" >/dev/null 2>&1; then
        return
    fi
    if [ -z "$asset_pattern" ]; then
        echo "warning: unsupported CPU architecture ($(uname -m)) for $bin_name; install manually from https://github.com/$repo/releases" >&2
        return
    fi

    echo "==> installing $bin_name $version from github.com/$repo"
    # CI runners share IPs, so unauthenticated API calls hit GitHub's rate
    # limit there; use its token when there is one.
    local url auth=()
    [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
    url=$(curl -fsSL "${auth[@]}" "https://api.github.com/repos/$repo/releases/tags/$version" \
        | grep -o "\"browser_download_url\": *\"[^\"]*${asset_pattern}[^\"]*\"" \
        | head -1 \
        | sed -E 's/.*"(https[^"]+)"/\1/')
    if [ -z "$url" ]; then
        echo "warning: no $bin_name $version release asset matching '$asset_pattern' found; install manually from https://github.com/$repo/releases" >&2
        return
    fi

    local tmp
    tmp=$(mktemp -d)
    curl -fsSL "$url" -o "$tmp/asset"
    case "$url" in
        *.tar.gz|*.tgz) tar -xzf "$tmp/asset" -C "$tmp" ;;
        *.zip) unzip -q "$tmp/asset" -d "$tmp" ;;
        *) echo "warning: unrecognized archive format for $bin_name: $url" >&2; rm -rf "$tmp"; return ;;
    esac

    mkdir -p "$LOCAL_BIN"
    local name found=0
    for name in "${bin_names[@]}"; do
        local match
        match=$(find "$tmp" -type f -name "$name" | head -1)
        if [ -n "$match" ]; then
            install -m755 "$match" "$LOCAL_BIN/$name"
            found=1
        fi
    done
    rm -rf "$tmp"

    if [ "$found" -eq 0 ]; then
        echo "warning: downloaded $bin_name release but found none of: ${bin_names[*]}" >&2
        return
    fi
    mkdir -p "$RELEASE_VERSION_DIR"
    echo "$version" >"$marker"
}

# doctor_releases <doctor ok fn> <doctor bad fn> <name>...: one line per
# pinned release tool.
doctor_releases() {
    local ok=$1 bad=$2 name
    shift 2
    for name; do
        if release_current "$name"; then
            "$ok" "$name ${RELEASE_VERSIONS[$name]}"
        elif [ -e "$LOCAL_BIN/$name" ]; then
            "$bad" "$name isn't the pinned ${RELEASE_VERSIONS[$name]} (run install.sh)"
        elif command -v "$name" >/dev/null 2>&1; then
            "$ok" "$name (installed outside install.sh)"
        else
            "$bad" "$name not on PATH"
        fi
    done
}

# outdated_releases <name>...: "name pinned -> latest" per pin behind its
# upstream's latest release. Returns 0 all current, 1 any behind, 2 a
# lookup failed.
outdated_releases() {
    local name latest status=0 auth=()
    [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
    for name; do
        latest=$(curl -fsSL "${auth[@]}" "https://api.github.com/repos/${RELEASE_REPOS[$name]}/releases/latest" \
            | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')
        if [ -z "$latest" ]; then
            echo "error: couldn't look up the latest $name release" >&2
            status=2
        elif [ "$latest" != "${RELEASE_VERSIONS[$name]}" ]; then
            echo "$name ${RELEASE_VERSIONS[$name]} -> $latest"
            [ "$status" -eq 2 ] || status=1
        fi
    done
    return "$status"
}

# Where a package wants a link but something else is already there (a real
# file, or a link stow doesn't own), move that aside into BACKUP_DIR so the
# repo version wins. (stow --adopt used to pull such files into the repo
# instead, silently replacing tracked content with the machine's copy.)
# The conflicts come from stow's own dry run, so its ignore rules apply.
BACKUP_DIR="$HOME/.local/state/dots/backup/$(date +%Y%m%d-%H%M%S)"

stow_conflicts() {
    stow -n -v --no-folding -d "$1" -t "$HOME" "$2" 2>&1 \
        | sed -n -e 's/.* over existing target \(.*\) since .*/\1/p' \
                 -e 's/.*existing target is not owned by stow: \(.*\)/\1/p'
}

backup_conflicts() {
    local rel
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        mkdir -p "$(dirname "$BACKUP_DIR/$rel")"
        mv -- "$HOME/$rel" "$BACKUP_DIR/$rel"
        echo "==> moved existing ~/$rel aside to ${BACKUP_DIR/#"$HOME"/\~}/$rel"
    done < <(stow_conflicts "$1" "$2")
}

# stow_packages <dir> <package>...: link each package into $HOME, moving
# whatever is in the way aside first.
stow_packages() {
    local dir=$1 pkg
    shift
    for pkg; do
        echo "==> stowing $pkg"
        backup_conflicts "$dir" "$pkg"
        stow -v --no-folding -d "$dir" -t "$HOME" "$pkg"
    done
}

# unstow_packages <dir> <package>...: remove the links a package made
# (used when a machine moves from desktop back to terminal).
unstow_packages() {
    local dir=$1 pkg
    shift
    for pkg; do
        [ -d "$dir/$pkg" ] || continue
        echo "==> unlinking $pkg"
        stow -D --no-folding -d "$dir" -t "$HOME" "$pkg" 2>/dev/null || true
    done
}

# Symlinks in $HOME that point into ~/.dots or ~/.rice at a file that no
# longer exists — left behind whenever a file is deleted or renamed in a
# package, since stow only ever adds links. One "link -> target" per line.
dangling_links() {
    { find "$HOME" -maxdepth 1 -xtype l -printf '%p -> %l\n'
      find "$HOME/.config" "$HOME/.local/bin" "$HOME/.local/share/applications" "$HOME/.agent-pool/bin" -xtype l -printf '%p -> %l\n'
    } 2>/dev/null | grep -E '\.(dots|rice)/' || true
}

prune_dangling_links() {
    local line
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        echo "==> removing dangling link ${line}"
        rm -f -- "${line%% -> *}"
    done < <(dangling_links)
}

# doctor_links <ok fn> <bad fn> <dir:pkg>...: stow's dry run lists exactly
# the links a real run would still make (LINK:) and the files it would
# refuse to replace (* cannot stow ...).
doctor_links() {
    local ok=$1 bad=$2 entry dir pkg out failed=0
    shift 2
    for entry; do
        pkg=${entry##*:}; dir=${entry%:*}
        out=$(stow -n -v --no-folding -d "$dir" -t "$HOME" "$pkg" 2>&1 || true)
        if grep -q '^LINK:' <<<"$out"; then
            "$bad" "${dir/#"$HOME"/\~}/$pkg: not linked: $(sed -n 's/^LINK: \([^ ]*\) =>.*/~\/\1/p' <<<"$out" | tr '\n' ' ')(run install.sh)"
            failed=1
        elif grep -q 'cannot stow' <<<"$out"; then
            "$bad" "${dir/#"$HOME"/\~}/$pkg: conflicts: $(sed -n 's/.*over existing target \([^ ]*\).*/~\/\1/p' <<<"$out" | tr '\n' ' ')"
            failed=1
        fi
    done
    return "$failed"
}

# Stowing new or changed unit files doesn't tell a running systemd --user
# about them.
reload_user_units() {
    systemctl --user daemon-reload >/dev/null 2>&1 || true
}

# Colors for the --doctor report; DOCTOR_FAILS/DOCTOR_WARNS count.
doctor_init() {
    DOCTOR_FAILS=0 DOCTOR_WARNS=0
    D_G="" D_R="" D_Y="" D_N=""
    if [ -t 1 ]; then D_G=$'\033[32m' D_R=$'\033[31m' D_Y=$'\033[33m' D_N=$'\033[0m'; fi
}
ok() { printf '  %sok%s    %s\n' "$D_G" "$D_N" "$*"; }
bad() { printf '  %sFAIL%s  %s\n' "$D_R" "$D_N" "$*"; DOCTOR_FAILS=$((DOCTOR_FAILS + 1)); }
warn() { printf '  %swarn%s  %s\n' "$D_Y" "$D_N" "$*"; DOCTOR_WARNS=$((DOCTOR_WARNS + 1)); }
