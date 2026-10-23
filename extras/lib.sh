# Sourced by extras' setup.sh scripts.

# pkg_install <dnf package>... -- <apt package>... -- <pacman package>...
# Installs whichever of the packages for this distro's package manager
# aren't installed yet; a no-op when they all are. Omit the trailing
# `-- <pacman package>...` entirely if there's no official Arch package.
pkg_install() {
    local dnf_pkgs=() apt_pkgs=() pacman_pkgs=() missing=() pkg
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do dnf_pkgs+=("$1"); shift; done
    [ "${1:-}" = "--" ] && shift
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do apt_pkgs+=("$1"); shift; done
    [ "${1:-}" = "--" ] && shift
    pacman_pkgs=("$@")

    if command -v dnf >/dev/null 2>&1; then
        for pkg in "${dnf_pkgs[@]}"; do rpm -q "$pkg" >/dev/null 2>&1 || missing+=("$pkg"); done
        [ ${#missing[@]} -eq 0 ] || sudo dnf install -y "${missing[@]}"
    elif command -v apt >/dev/null 2>&1; then
        for pkg in "${apt_pkgs[@]}"; do dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg"); done
        [ ${#missing[@]} -eq 0 ] || { sudo apt update && sudo apt install -y "${missing[@]}"; }
    elif command -v pacman >/dev/null 2>&1; then
        for pkg in "${pacman_pkgs[@]}"; do pacman -Qq "$pkg" >/dev/null 2>&1 || missing+=("$pkg"); done
        [ ${#missing[@]} -eq 0 ] || sudo pacman -S --needed --noconfirm "${missing[@]}"
    else
        echo "error: no supported package manager (apt/dnf/pacman)" >&2
        return 1
    fi
}
