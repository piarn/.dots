vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- No remote plugins here: skip probing for each language's host
vim.g.loaded_python3_provider = 0
vim.g.loaded_node_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0

local opt = vim.opt

opt.number = true
opt.relativenumber = true

opt.ignorecase = true
opt.smartcase = true

opt.scrolloff = 8
opt.signcolumn = "yes"
opt.cursorline = true
opt.laststatus = 3 -- one statusline for the whole screen
opt.showmode = false -- lualine shows it

opt.undofile = true

opt.updatetime = 250
opt.timeoutlen = 300

opt.splitright = true
opt.splitbelow = true

opt.termguicolors = true
opt.clipboard = "unnamedplus"
-- Over ssh there's no Wayland clipboard to reach: OSC 52 asks the terminal
-- (foot, through tmux's set-clipboard) to set the local one instead.
if vim.env.SSH_TTY and not vim.env.WAYLAND_DISPLAY then
  vim.g.clipboard = "osc52"
end
-- Files changed under nvim (git in the next tmux pane, a formatter) reload
-- when it's focused again; tmux forwards focus (focus-events), see autocmds.
opt.autoread = true
opt.wrap = false
opt.mouse = "a"

opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.softtabstop = 2

-- native treesitter folding, start fully unfolded
opt.foldmethod = "expr"
opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
opt.foldlevel = 99
