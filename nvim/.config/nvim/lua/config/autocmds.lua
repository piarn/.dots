local au = vim.api.nvim_create_autocmd
local group = vim.api.nvim_create_augroup("dots", { clear = true })

-- Panels: windows that only make sense next to code. When the last code
-- window closes, they go too, so :q quits instead of leaving a lone tree.
local panel_ft = {
  ["neo-tree"] = true,
  aerial = true,
  trouble = true,
  qf = true,
  ["dap-view"] = true,
  ["dap-repl"] = true,
  ["dap-view-term"] = true,
}

local function is_panel(win)
  local buf = vim.api.nvim_win_get_buf(win)
  return panel_ft[vim.bo[buf].filetype] or vim.b[buf].terminal_panel
    or vim.api.nvim_win_get_config(win).relative ~= ""
end

au("QuitPre", {
  group = group,
  desc = "Close the panels along with the last code window",
  callback = function()
    local current = vim.api.nvim_get_current_win()
    if is_panel(current) then
      return
    end
    local panels = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if win ~= current then
        if not is_panel(win) then
          return -- another code window remains; nothing to do
        end
        table.insert(panels, win)
      end
    end
    local term = require("config.terminal").buf()
    for _, win in ipairs(panels) do
      if vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    if term and #vim.api.nvim_list_tabpages() == 1 then
      pcall(vim.api.nvim_buf_delete, term, { force = true }) -- running shell would block :q
    end
  end,
})

au("TextYankPost", {
  group = group,
  desc = "Flash what was yanked",
  callback = function()
    vim.hl.on_yank({ timeout = 150 })
  end,
})

au("TermOpen", {
  group = group,
  desc = "Terminals: no gutter",
  callback = function()
    vim.wo.number = false
    vim.wo.relativenumber = false
    vim.wo.signcolumn = "no"
  end,
})

-- Pick up changes made outside nvim (git or a formatter in another tmux
-- pane) as soon as it's focused again; a buffer with unsaved edits asks first.
au({ "FocusGained", "BufEnter", "TermLeave" }, {
  group = group,
  desc = "Reload files changed outside nvim",
  callback = function()
    if vim.fn.getcmdwintype() == "" then vim.cmd.checktime() end
  end,
})
