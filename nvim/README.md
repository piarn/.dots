# nvim

A terminal Zed whose editing language is vim. `nvim/.config/nvim`, stowed to
`~/.config/nvim/`. Space is the leader (tmux's leader too, but only in tmux's
TMUX mode, where keys never reach nvim — so they never collide).

## Layout

| Path | What |
| --- | --- |
| `lua/config/keymaps.lua` | **every global key** — the grammar below, in one file |
| `lua/config/options.lua` | options |
| `lua/config/lsp.lua` | server settings, the extras' servers, diagnostics look, mason tools |
| `lua/config/run.lua` | `␣r`: run / build / test per language |
| `lua/config/terminal.lua` | the bottom terminal panel and the lazygit float |
| `lua/config/autocmds.lua` | panels close with the last code window, yank flash |
| `lua/config/theme.lua` | loads `lua/config/palette.lua`; gives lualine/bufferline the palette |
| `lua/plugins/*.lua` | plugin specs only — no keys |

New files need `stow -R --no-folding -t ~ nvim` (links are per file).

## The grammar

1. **Vim first.** Operators, motions, textobjects, `g` gotos and `[`/`]` pairs
   are Neovim's own wherever it has one; nothing overrides them.
2. **`Space` + a mnemonic group** for what vim doesn't have.
3. **lowercase = do it, Shift = the bigger version** — as in tmux and sway.
4. **Panels are one letter** after the leader.
5. **`Ctrl+Space` and `Ctrl+h/j/k/l` belong to tmux.** Alt reaches nvim (tmux
   is in SHELL mode while you edit).

Forgot a key? `␣:` lists every action with its key and runs the one you pick;
pausing after `␣` or a group letter shows what's in it.

## Screen

Opens clean: code, buffer tabs on top, one statusline. Panels on demand:

```
┌ tabs ─────────────────────────────────────────────────┐
│ ␣e tree │            code               │ ␣o outline  │
│         │                               │             │
├─────────┴───────────────────────────────┴─────────────┤
│ ␣p/␣P problems · ␣t terminal · debug view (auto)      │
├───────────────────────────────────────────────────────┤
│ NORMAL  branch  file  ●2 ▲1        gopls  go   12:4   │
└───────────────────────────────────────────────────────┘
```

`:q` in the last code window takes the panels with it.

## Keys

**Vim's own (learn these first)**

| Key | Action |
| --- | --- |
| `gd` / `grr` / `gri` / `grt` | definition / references / implementation / type |
| `K` | hover docs (twice: into the float) |
| `gO` | symbols in this file |
| `gra` / `grn` | code action / rename (also `␣ca` / `␣cr`) |
| `[d ]d` | previous / next diagnostic |
| `[b ]b` | previous / next buffer (tab) |
| `[q ]q` | previous / next quickfix entry (build errors) |
| `[c ]c` | previous / next git hunk |
| `[f ]f`, `[F ]F` | previous / next function start, end |
| `af if`, `ac ic`, `aa ia` | function, class, argument textobjects: `daf`, `cia`, `vac` |
| `s` / `S` | flash: jump to any visible spot / select a syntax node |
| `gc{motion}`, `gcc` | comment |
| `ys{motion}{char}`, `ds{char}`, `cs{old}{new}` | surround |
| `Alt+j` / `Alt+k` | move line / selection |
| `Ctrl+h/j/k/l` | window left/down/up/right — crosses into tmux panes |

**Top level**

| Key | Action |
| --- | --- |
| `␣␣` | find file |
| `␣/` | grep project |
| `␣:` | command palette (every action and its key) |
| `␣,` | switch buffer |
| `␣e` / `␣E` | tree / reveal current file in it |
| `␣o` | outline |
| `␣p` / `␣P` | problems: this file / whole project |
| `␣t` | terminal panel (`Esc Esc` back to normal mode) |
| `␣w` / `␣W` | close buffer (asks if unsaved) / close all others |
| `␣\` / `␣-` | split right / below — the same keys as tmux |

**Groups**

| Group | Keys |
| --- | --- |
| `␣f` find | `ff` files · `fg` grep · `fw` word / selection · `fr` recent (project) · `fs` workspace symbols · `fh` help · `fc` ex commands · `f.` resume |
| `␣c` code | `ca` action · `cr` rename · `cf` format · `cd` line diagnostics · `cl` restart LSP |
| `␣g` git | `gg` lazygit · `gs` stage hunk/lines · `gS` stage file · `gr` reset hunk/lines · `gp` preview · `gb` blame · `gd` diff file |
| `␣r` run | `rr` run · `rb` build → problems · `rt` test nearest · `rT` test file/package · `rl` repeat last |
| `␣d` debug | `db` breakpoint · `dB` conditional · `dc` start/continue · `dn` over · `ds` in · `do` out · `dK` inspect · `dv` view · `dq` stop · **`dd` DEBUG mode** |
| `␣u` toggle | `uh` hardtime · `uw` wrap · `un` relative numbers · `ui` inlay hints · `ub` inline blame · `ud` diagnostic text |

**DEBUG mode** (`␣dd`) is tmux's modal idea applied to stepping: the `␣d`
group stays open and its keys work bare — `n` over, `s` in, `o` out, `c`
continue, `b` breakpoint, `K` inspect — until `Esc`.

## Run, build, test

`␣r` picks the command from the buffer's filetype and the project root
(`go.mod`, `Cargo.toml`, `build.zig`, `package.json`, `Makefile`, ...). Run and
test go to the terminal panel; build runs in the background and its errors
fill the quickfix list, shown in the problems panel (`[q ]q` walk it).

| Language | `rr` | `rb` | `rT` | `rt` (nearest) |
| --- | --- | --- | --- | --- |
| Go | `go run <dir>` | `go build ./... && go vet ./...` | `go test -v <dir>` | `func TestX` above the cursor |
| Python | `python3 <file>` | `ruff check` | `pytest <file>` | `def test_x` above |
| Rust | `cargo run` | `cargo build` | `cargo test` | `#[test] fn x` above |
| C / C++ | `make run`, else compile + run the file | `make` / cmake / `-fsyntax-only` | `make test` / `ctest` | — |
| Zig | `zig build run` / `zig run` | `zig build` / `build-exe` | `zig test <file>` | `test "name"` above |
| Nim | `nim r <file>` | `nim check` | `nimble test` | — |
| JS / TS | `node` / `npx tsx <file>` | `npm run build` | `npm test` | — |
| sh / bash / fish | the interpreter | `shellcheck` / `fish --no-execute` | — | — |

## Debugger

nvim-dap + nvim-dap-view. The view opens at the bottom when a session starts
and closes when it ends; variable values show inline. `␣dc` asks which
configuration to run.

| Language | Adapter | From |
| --- | --- | --- |
| Go | `dlv dap` | `extras/go` |
| C, C++, Rust, Zig | `lldb-dap` (asks for the binary; guesses `target/debug/<dir>` / `zig-out/bin/<dir>`) | the distro's `lldb` package |
| Python | debugpy, in the project's `.venv` if there is one | mason (installed automatically) |

## Learning: hardtime

hardtime blocks `hjkl`/arrow spam after 3 repeats and names the better motion
(`5j`, `}`, `Ctrl+d`, `f`, `w`, ...). That's the point: the block is the
lesson. `␣uh` turns it off for a session if you're pairing or tired. It stays
out of the panels.

## Language servers

mason installs what no language extra does (basedpyright, ruff, lua_ls, bashls,
yamlls, jsonls, ts_ls, zls, docker) plus debugpy and the formatters
(stylua, shfmt, goimports, gofumpt). gopls, clangd, rust-analyzer and
nimlangserver come from `extras/<lang>` and are only enabled when on `PATH`.
Linters run only when installed (`golangci-lint` isn't part of any extra).

## Theme

Chrome only, from `lua/config/palette.lua` (the fixed black/gray palette):
statusline, tabs, tree, outline, problems, debugger signs. Code colors are
never touched.
