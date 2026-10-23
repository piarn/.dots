-- The key grammar. Every global key lives here, the way tmux.conf's direct
-- binds block holds tmux's; nvim/README.md tables the lot.
--
-- 1. Vim first: operators, motions, textobjects, g-gotos and [ ] pairs stay
--    Neovim's own (gd grr gri grt gra grn K gO [d ]d [b ]b [q ]q) — nothing
--    here overrides one.
-- 2. Space + a mnemonic group for what vim doesn't have.
-- 3. lowercase = do it, Shift = the bigger version (as in tmux and sway).
-- 4. Panels are one letter after the leader.
-- 5. Ctrl+Space and Ctrl+h/j/k/l belong to tmux (vim-modes, the navigator);
--    Alt reaches nvim because tmux is in SHELL mode while you edit.
--
-- Plugin modules are only require()d inside the functions, so lazy.nvim still
-- loads each plugin the first time its key is used.

local map = vim.keymap.set

local function cmd(c)
  return "<cmd>" .. c .. "<cr>"
end

local function fzf(picker, opts)
  return function()
    require("fzf-lua")[picker](opts or {})
  end
end

-- which-key group names (registered from plugins/which-key.lua)
local groups = {
  { "<leader>f", group = "find" },
  { "<leader>c", group = "code" },
  { "<leader>g", group = "git" },
  { "<leader>r", group = "run" },
  { "<leader>d", group = "debug" },
  { "<leader>u", group = "toggle" },
}

------------------------------------------------------------------------------
-- Editing (vim, sharpened)
------------------------------------------------------------------------------

map("n", "<A-j>", "<cmd>m .+1<cr>==", { desc = "Move line down" })
map("n", "<A-k>", "<cmd>m .-2<cr>==", { desc = "Move line up" })
map("v", "<A-j>", ":m '>+1<cr>gv=gv", { desc = "Move selection down" })
map("v", "<A-k>", ":m '<-2<cr>gv=gv", { desc = "Move selection up" })

map("v", "<", "<gv", { desc = "Indent left, keep selection" })
map("v", ">", ">gv", { desc = "Indent right, keep selection" })

map("n", "<Esc>", cmd("nohlsearch"), { desc = "Clear search highlight" })

-- s / S: jump anywhere on screen / select a treesitter node
map({ "n", "x", "o" }, "s", function() require("flash").jump() end, { desc = "Flash jump" })
map({ "n", "x", "o" }, "S", function() require("flash").treesitter() end, { desc = "Flash treesitter" })

-- treesitter textobjects: f function, c class, a argument (daf, cia, vac, ...)
local textobjects = {
  f = "function",
  c = "class",
  a = "parameter",
}
for key, obj in pairs(textobjects) do
  for _, side in ipairs({ { "a", "outer" }, { "i", "inner" } }) do
    local capture = ("@%s.%s"):format(obj, side[2])
    map({ "x", "o" }, side[1] .. key, function()
      require("nvim-treesitter-textobjects.select").select_textobject(capture, "textobjects")
    end, { desc = obj .. " (" .. side[2] .. ")" })
  end
end

-- ]f [f: next / previous function start; ]F [F: its end
local function move(fn, capture)
  return function()
    require("nvim-treesitter-textobjects.move")[fn](capture, "textobjects")
  end
end
map({ "n", "x", "o" }, "]f", move("goto_next_start", "@function.outer"), { desc = "Next function" })
map({ "n", "x", "o" }, "[f", move("goto_previous_start", "@function.outer"), { desc = "Previous function" })
map({ "n", "x", "o" }, "]F", move("goto_next_end", "@function.outer"), { desc = "Next function end" })
map({ "n", "x", "o" }, "[F", move("goto_previous_end", "@function.outer"), { desc = "Previous function end" })

-- ]c [c: next / previous git hunk (vim's own in a diff window)
local function hunk(dir)
  return function()
    if vim.wo.diff then
      vim.cmd.normal({ dir == "next" and "]c" or "[c", bang = true })
    else
      require("gitsigns").nav_hunk(dir)
    end
  end
end
map("n", "]c", hunk("next"), { desc = "Next git hunk" })
map("n", "[c", hunk("prev"), { desc = "Previous git hunk" })

------------------------------------------------------------------------------
-- Windows: Ctrl+h/j/k/l crosses nvim splits and tmux panes alike
------------------------------------------------------------------------------

map("n", "<C-h>", cmd("TmuxNavigateLeft"), { desc = "Window left" })
map("n", "<C-j>", cmd("TmuxNavigateDown"), { desc = "Window down" })
map("n", "<C-k>", cmd("TmuxNavigateUp"), { desc = "Window up" })
map("n", "<C-l>", cmd("TmuxNavigateRight"), { desc = "Window right" })

-- in a terminal: Esc Esc leaves terminal mode, Ctrl+h/j/k/l still moves out
-- (a fast Esc Esc reaches nvim through tmux as one <M-Esc>, hence both)
map("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Terminal: normal mode" })
map("t", "<M-Esc>", "<C-\\><C-n>", { desc = "Terminal: normal mode" })
map("t", "<C-h>", "<C-\\><C-n>" .. cmd("TmuxNavigateLeft"), { desc = "Window left" })
map("t", "<C-j>", "<C-\\><C-n>" .. cmd("TmuxNavigateDown"), { desc = "Window down" })
map("t", "<C-k>", "<C-\\><C-n>" .. cmd("TmuxNavigateUp"), { desc = "Window up" })
map("t", "<C-l>", "<C-\\><C-n>" .. cmd("TmuxNavigateRight"), { desc = "Window right" })

map("n", "<leader>\\", cmd("vsplit"), { desc = "Split right" })
map("n", "<leader>-", cmd("split"), { desc = "Split below" })

------------------------------------------------------------------------------
-- Top level: find, panels, buffers
------------------------------------------------------------------------------

map("n", "<leader><leader>", fzf("files"), { desc = "Find file" })
map("n", "<leader>/", fzf("live_grep"), { desc = "Grep project" })
map("n", "<leader>:", fzf("keymaps"), { desc = "Command palette (every action + its key)" })
map("n", "<leader>,", fzf("buffers"), { desc = "Switch buffer" })

map("n", "<leader>e", cmd("Neotree toggle"), { desc = "Tree" })
map("n", "<leader>E", cmd("Neotree reveal"), { desc = "Tree: reveal current file" })
map("n", "<leader>o", cmd("AerialToggle! right"), { desc = "Outline" })
map("n", "<leader>p", cmd("Trouble diagnostics toggle filter.buf=0"), { desc = "Problems (file)" })
map("n", "<leader>P", cmd("Trouble diagnostics toggle"), { desc = "Problems (project)" })
map("n", "<leader>t", function() require("config.terminal").toggle() end, { desc = "Terminal panel" })

-- Close a buffer without closing its window (another buffer takes its place).
local function close_buffer(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if vim.bo[buf].modified then
    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
    local choice = vim.fn.confirm(("Save changes to %s?"):format(name ~= "" and name or "[No Name]"), "&Yes\n&No\n&Cancel")
    if choice == 1 then
      vim.api.nvim_buf_call(buf, function() vim.cmd.write() end)
    elseif choice ~= 2 then
      return
    end
  end
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    vim.api.nvim_win_call(win, function()
      local alt = vim.fn.bufnr("#")
      if alt > 0 and alt ~= buf and vim.fn.buflisted(alt) == 1 then
        vim.cmd.buffer(alt)
      else
        vim.cmd("silent! bprevious")
      end
      if vim.api.nvim_win_get_buf(win) == buf then
        vim.cmd.enew()
      end
    end)
  end
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
end

map("n", "<leader>w", function() close_buffer() end, { desc = "Close buffer" })
map("n", "<leader>W", function()
  local current, kept = vim.api.nvim_get_current_buf(), 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= current and vim.bo[buf].buflisted then
      if vim.bo[buf].modified then
        kept = kept + 1
      else
        vim.api.nvim_buf_delete(buf, {})
      end
    end
  end
  if kept > 0 then
    vim.notify(("kept %d unsaved buffer(s)"):format(kept), vim.log.levels.WARN)
  end
end, { desc = "Close all other buffers" })

------------------------------------------------------------------------------
-- ␣f find
------------------------------------------------------------------------------

map("n", "<leader>ff", fzf("files"), { desc = "Files" })
map("n", "<leader>fg", fzf("live_grep"), { desc = "Grep" })
map({ "n", "x" }, "<leader>fw", function()
  if vim.fn.mode():match("[vV]") then
    require("fzf-lua").grep_visual()
  else
    require("fzf-lua").grep_cword()
  end
end, { desc = "Grep word / selection" })
map("n", "<leader>fr", fzf("oldfiles", { cwd_only = true }), { desc = "Recent files (project)" })
map("n", "<leader>fs", fzf("lsp_live_workspace_symbols"), { desc = "Workspace symbols" })
map("n", "<leader>fh", fzf("helptags"), { desc = "Help" })
map("n", "<leader>fc", fzf("commands"), { desc = "Ex commands" })
map("n", "<leader>f.", fzf("resume"), { desc = "Resume last picker" })

------------------------------------------------------------------------------
-- ␣c code (gd / grr / gri / grt / K / gO are vim's own, see LspAttach below)
------------------------------------------------------------------------------

map({ "n", "x" }, "<leader>ca", vim.lsp.buf.code_action, { desc = "Code action" })
map("n", "<leader>cr", vim.lsp.buf.rename, { desc = "Rename symbol" })
map({ "n", "x" }, "<leader>cf", function() require("conform").format({ async = true, lsp_format = "fallback" }) end, { desc = "Format" })
map("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Line diagnostics" })
map("n", "<leader>cl", cmd("lsp restart"), { desc = "Restart LSP" })

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("lsp-keys", { clear = true }),
  desc = "LSP buffer keys + inlay hints",
  callback = function(ev)
    map("n", "gd", vim.lsp.buf.definition, { buffer = ev.buf, desc = "Goto definition" })
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client:supports_method("textDocument/inlayHint") then
      vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
    end
  end,
})

------------------------------------------------------------------------------
-- ␣g git
------------------------------------------------------------------------------

local function gs(fn, ...)
  local args = { ... }
  return function()
    require("gitsigns")[fn](unpack(args))
  end
end

map("n", "<leader>gs", gs("stage_hunk"), { desc = "Stage hunk (again: unstage)" })
map("x", "<leader>gs", function() require("gitsigns").stage_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, { desc = "Stage lines" })
map("n", "<leader>gS", gs("stage_buffer"), { desc = "Stage file" })
map("n", "<leader>gr", gs("reset_hunk"), { desc = "Reset hunk" })
map("x", "<leader>gr", function() require("gitsigns").reset_hunk({ vim.fn.line("."), vim.fn.line("v") }) end, { desc = "Reset lines" })
map("n", "<leader>gp", gs("preview_hunk"), { desc = "Preview hunk" })
map("n", "<leader>gb", gs("blame_line", { full = true }), { desc = "Blame line" })
map("n", "<leader>gd", gs("diffthis"), { desc = "Diff file vs index" })

------------------------------------------------------------------------------
-- ␣r run (config/run.lua)
------------------------------------------------------------------------------

local function run(fn, arg)
  return function()
    require("config.run")[fn](arg)
  end
end

map("n", "<leader>rr", run("run"), { desc = "Run" })
map("n", "<leader>rb", run("build"), { desc = "Build → problems" })
map("n", "<leader>rt", run("test", "nearest"), { desc = "Test nearest" })
map("n", "<leader>rT", run("test", "file"), { desc = "Test file / package" })
map("n", "<leader>rl", run("last"), { desc = "Repeat last" })

------------------------------------------------------------------------------
-- ␣d debug — ␣dd is DEBUG mode: the bare keys of this group (n s o c b K)
-- keep working until Esc
------------------------------------------------------------------------------

local function dap(fn, ...)
  local args = { ... }
  return function()
    require("dap")[fn](unpack(args))
  end
end

map("n", "<leader>db", dap("toggle_breakpoint"), { desc = "Breakpoint" })
map("n", "<leader>dB", function()
  require("dap").set_breakpoint(vim.fn.input("Condition: "))
end, { desc = "Conditional breakpoint" })
map("n", "<leader>dc", dap("continue"), { desc = "Start / continue" })
map("n", "<leader>dn", dap("step_over"), { desc = "Step over (next)" })
map("n", "<leader>ds", dap("step_into"), { desc = "Step in" })
map("n", "<leader>do", dap("step_out"), { desc = "Step out" })
map("n", "<leader>dK", function() require("dap-view").hover() end, { desc = "Inspect under cursor" })
map("n", "<leader>dv", function() require("dap-view").toggle() end, { desc = "Debug view" })
map("n", "<leader>dq", dap("terminate"), { desc = "Stop" })
map("n", "<leader>dd", function()
  require("which-key").show({ keys = "<leader>d", loop = true })
end, { desc = "DEBUG mode (Esc leaves)" })

------------------------------------------------------------------------------
-- ␣u toggles
------------------------------------------------------------------------------

local function toggle_opt(name)
  return function()
    vim.wo[name] = not vim.wo[name]
    vim.notify(name .. ": " .. (vim.wo[name] and "on" or "off"))
  end
end

map("n", "<leader>uh", cmd("Hardtime toggle"), { desc = "Hardtime (habit breaker)" })
map("n", "<leader>uw", toggle_opt("wrap"), { desc = "Wrap" })
map("n", "<leader>un", toggle_opt("relativenumber"), { desc = "Relative numbers" })
map("n", "<leader>ui", function()
  local on = not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 })
  vim.lsp.inlay_hint.enable(on, { bufnr = 0 })
  vim.notify("inlay hints: " .. (on and "on" or "off"))
end, { desc = "Inlay hints" })
map("n", "<leader>ub", gs("toggle_current_line_blame"), { desc = "Inline blame" })
map("n", "<leader>ud", function()
  local on = not vim.diagnostic.config().virtual_text
  vim.diagnostic.config({ virtual_text = on and { spacing = 2, prefix = "●" } or false })
  vim.notify("diagnostic text: " .. (on and "on" or "off"))
end, { desc = "Diagnostic text" })

return { groups = groups }
