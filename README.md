# .dotfiles

The terminal: shell (fish, bash), editor (nvim), tmux, git and the TUI
tools (yazi, lazygit, lazydocker, fzf, ripgrep, ...), plus the
[agent pool](#agent-pool) that runs `claude` across two subscriptions.
Managed with [GNU Stow](https://www.gnu.org/software/stow/): each
top-level directory (`bash`, `fish`, `nvim`, ...) is a stow package whose
contents mirror `$HOME`.

The desktop (sway, quickshell, the GUI apps) is
[`~/.rice`](https://github.com/piarn/.rice)'s, layered on top only where
it's wanted.

## Setup

```
git clone <repo> ~/.dots
cd ~/.dots
./install.sh terminal     # work laptop, server: the terminal only
./install.sh desktop      # own laptop: terminal + ~/.rice's sway/quickshell desktop
./install.sh              # re-run with whichever profile this machine has
```

| Profile | What it installs |
| --- | --- |
| `terminal` | this repo's packages, the CLI tools, `~/.rice` cloned for the palette (nothing desktop is linked or installed) |
| `desktop` | `terminal`, then `~/.rice/install.sh`: sway, quickshell, kitty/foot, the flatpaks, the login screen and session services |

The profile is saved in `~/.config/dots/profile`, so a bare `./install.sh`
keeps it. Switching from `desktop` to `terminal` unlinks the desktop
configs (`~/.rice/install.sh --uninstall`); packages stay installed.

`install.sh` installs whatever's missing from `.bootstrap/packages.txt`
(apt/dnf/pacman), then symlinks each package into `$HOME`. Anything
already sitting at a target path (e.g. a distro's default `~/.bashrc`) is
moved aside into `~/.local/state/dots/backup/<timestamp>/` first, so the
repo version always wins and the old file is kept for reference. Finally
it runs `dots-reload`, which pushes the new configs into whatever is
already running (the tmux server, fish; on desktop it hands kitty, sway
and quickshell to `~/.rice`'s `rice-reload`); run it by hand any time a
config changes under a running session.

Tested distro families: Fedora (dnf), Debian/Ubuntu (apt), Arch (pacman).

`.bootstrap/` holds what `install.sh` drives: system packages
(`packages.txt`), the installer library shared with `~/.rice/install.sh`
(`lib.sh`: package managers, pinned GitHub releases, stow with backups,
the profile) and the one-time fish plugin-manager setup (`fish/`). A few
`packages.txt` entries install a binary whose name doesn't match the
package name (`ripgrep`→`rg`, `neovim`→`nvim`) or a differently-cased
package name on apt — `lib.sh` handles both via small override maps.

`yazi`, `lazygit`, `lazydocker` and `mise` aren't packaged for apt/dnf
(and `tree-sitter`, which nvim builds its parsers with, is too old on
Debian/Ubuntu), so `install.sh` downloads each from its project's GitHub
releases into `~/.local/bin` instead, pinned to the tag in
`RELEASE_VERSIONS` (bump it and re-run to upgrade; skipped if installed
some other way).

### Checking a machine

```
./install.sh --doctor
```

Read-only: lists what `install.sh` would still install or link (via
stow's dry run), links left dangling by files since removed from a
package (a normal `install.sh` run deletes those), the agent pool's
accounts, and whether tmux is running an older config than the one on
disk (fix: `dots-reload`). On the desktop profile it goes on to
`~/.rice/install.sh --doctor` (the login screen, sway, quickshell, session
services). Exits 1 if anything failed.

### When things break

The desktop's recovery (quickshell, sway, the lock screen, a session that
won't start) is in [`~/.rice`'s README](https://github.com/piarn/.rice#when-things-break).
From the terminal side: every machine can log in to a plain shell (ly's
**Terminal** session on desktop, any TTY or ssh everywhere), and
everything in this repo works from there.

CI (`.github/workflows`) runs shellcheck, `fish --no-execute` and
`tests/run.sh` on every push, and `./install.sh --ci` in fresh Fedora,
Debian, Ubuntu 24.04 and Arch containers whenever the installer changes
(and weekly): every package and the release-binary tools — the parts that
break when a distro renames or drops a package.

## Agent pool

`claude` runs on two Claude subscriptions, `claude1` and `claude2`, and
rolls over to the other one when it hits a usage limit — mid-conversation,
picking the same conversation back up.

```
~/.agent-pool/
  claude1/   claude2/    one CLAUDE_CONFIG_DIR per subscription: its login
                         (.credentials.json) and .claude.json, nothing else
  shared/                sessions, prompt history, settings, CLAUDE.md, memory,
                         plugins, skills, agents, commands — linked into both
  state/                 which account is active, recorded limits, last usage
  bin/  lib/             stowed from ./agent-pool
```

```
agent-pool                     status: accounts, active one, limits, 5h/7d usage
agent-pool login claude2       log a subscription in (once per account)
agent-pool use claude2         start new sessions on claude2
agent-pool next                switch to the next usable account
agent-pool clear               forget recorded limits
```

How the rollover works:

- `~/.agent-pool/bin/claude` sits ahead of the real `claude` on PATH
  (`config.fish`, `.bashrc`, `environment.d`); claude's own updater keeps
  managing `~/.local/bin/claude`. It starts claude on the active account,
  or the next one if the active one is at its limit.
- The status line (`lib/statusline`) shows the account and the plan's 5h /
  7d meters, and records them, so a new session never starts on an
  account it already saw full.
- When a turn fails with a usage limit, Claude Code's `StopFailure` hook
  (`lib/on-limit`, registered in the shared `settings.json`) records when
  the limit resets, and — if the other account is usable — ends that
  claude. The wrapper then runs `claude --resume <same session>` on the
  other account with "Continue where you left off", keeping flags like
  `--model` and the permission mode. Sessions live in `shared/projects`,
  so the other account has the whole conversation.
- If both accounts are limited, claude starts on the one that frees up
  first and says when.

`AGENT_POOL_ACCOUNT=claude2 claude` pins one run to an account. A claude
started from inside another (`CLAUDECODE` set) skips the pool and keeps
the account it inherited. The first time an account opens a directory it
asks to trust it, once.

## .rice

[`~/.rice`](https://github.com/piarn/.rice) owns the palette the configs
here take their colors from (tmux, nvim, fish, fzf, eza, yazi, lazygit,
lazydocker), and the desktop. Both profiles clone it over https (pushes go
over ssh), fast-forward it when its branch has an upstream, and render the
current theme (`~/.rice/bin/apply-theme`); only the desktop profile
installs anything from it. Every config here still works without it,
falling back to neutral colors.

## tmux

Vim-style modes, one session per "case" with persistence across reboots, a
session/window/pane tree popup, and direct Alt binds — see
[`tmux/README.md`](tmux/README.md).

## nvim

A terminal Zed whose editing language is vim: Space-leader grammar mirroring
tmux and sway (one file, `lua/config/keymaps.lua`), toggleable tree / outline /
problems / terminal panels, run-build-test per language, a debugger with a
modal stepping layer, and hardtime breaking hjkl habits — see
[`nvim/README.md`](nvim/README.md).

## Extras

Opt-in features that aren't part of the base setup live under
[`extras/`](extras): `install.sh` never installs or links them on its own.
Enable them per machine:

```
~/.dots/extras/extras.sh list             # * marks the enabled ones
~/.dots/extras/extras.sh enable backup    # install it, link it in
~/.dots/extras/extras.sh disable backup   # unlink it (installed packages stay)
```

The enabled list is kept in the untracked `.extras-enabled`, and
`install.sh` re-links whatever is on it. Each extra is a directory with a
`setup.sh` (installs its dependencies, idempotent) and/or a `home/` stow
package. An extra with a desktop half (say, a quickshell panel) keeps
that in `~/.rice/desktop/extras/<name>/home`, linked only on the desktop
profile. The VPN extras (and their panels) were dropped for now; they're
on the `gui-archive` branch.

### Languages

One extra per language, each just a `setup.sh` that installs the distro's
toolchain plus the editor tooling (nothing is linked into `$HOME`):

| Extra | What it adds |
| --- | --- |
| `c` | gcc, clang, make, cmake, gdb, clangd |
| `go` | Go, plus `gopls` and `dlv` via `go install` (into `$(go env GOPATH)/bin`) |
| `json` | jq (nvim formats JSON with it) |
| `lua` | Lua 5.4, LuaJIT, luarocks |
| `nim` | Nim + nimble + `nimlangserver`; Fedora has no Nim package, so there it comes from choosenim into `~/.nimble/bin` (update: `choosenim update stable`) |
| `node` | Node.js + npm |
| `python` | Python 3 with pip/venv/headers, pipx, uv |
| `rust` | rustc, cargo, rust-analyzer |
| `yaml` | yq + yamllint (nvim formats/lints YAML with them); Debian/Ubuntu's `yq` is a different tool, so there only yamllint |
| `zig` | Zig (packaged on Fedora/Arch; Debian/Ubuntu depends on the release) |

### backup

`extras.sh enable backup` installs restic and a daily `backup.timer`
snapshotting `~` (minus caches, Steam, toolchains, `node_modules` — see
`extras/backup/home/.config/backup/excludes`), then keeps 7 daily, 4
weekly and 12 monthly snapshots. Per machine, in `~/.config/backup/`:
`env` (where to — a disk, `sftp:host:/path`, any restic backend — and
what to keep) and a generated `password`: **keep a copy of it elsewhere**,
the backup is unreadable without it. Then once: `backup init`.

`backup` with no arguments runs a backup like the timer does; anything else
goes to restic with the repository filled in: `backup snapshots`,
`backup restore latest --target /tmp/r --include ~/notes`,
`backup mount ~/mnt`. A failed run sends a notification.

Extras can ship systemd timers (`home/.config/systemd/user/*.timer`);
`extras.sh` enables them on `enable` and disables them on `disable`.

## Git

Commits and tags are signed with the ssh key named in
`.gitconfig.identity.github` (`~/.ssh/keys/github`); for GitHub to show them
as Verified, add that key's `.pub` once more under Settings → SSH keys as
a **Signing key**. `git log --show-signature` verifies locally against
`git/.config/git/allowed_signers`. A `.gitconfig.identity.work` should set
its own `signingkey` (or `[commit] gpgsign = false`). Diffs go through
delta (git and lazygit), with histogram diffs, zdiff3 conflict markers,
rerere and prune-on-fetch on.

## Toolchains

[mise](https://mise.jdx.dev) (installed from its GitHub release) pins
go/node/python/... per project: `mise use go@1.24` in a project writes a
`mise.toml`, and fish switches versions on `cd` (`conf.d/mise.fish`).
Outside a pinned project the distro's toolchains are used as before.

## Adding a package

```
mkdir -p newpkg/.config/newtool
# add files under newpkg/... mirroring their $HOME path
```

Then add `newpkg` to the `PACKAGES` array in `install.sh`.
