-- The bottom terminal panel: one persistent shell per nvim, toggled with ␣t.
-- Hiding the panel keeps the shell (and whatever runs in it) alive; run.lua
-- sends its commands here. Not a buffer tab: it's unlisted.
local M = {}

local state = { buf = nil, win = nil }

local function buf_valid()
  return state.buf ~= nil and vim.api.nvim_buf_is_valid(state.buf)
end

function M.is_open()
  return state.win ~= nil
    and vim.api.nvim_win_is_valid(state.win)
    and buf_valid()
    and vim.api.nvim_win_get_buf(state.win) == state.buf
end

function M.buf()
  return buf_valid() and state.buf or nil
end

-- Open the panel along the bottom of the whole screen and focus it.
local function open()
  vim.cmd("botright split")
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(state.win, math.floor(vim.o.lines * 0.3))

  if buf_valid() then
    vim.api.nvim_win_set_buf(state.win, state.buf)
  else
    vim.cmd.terminal()
    state.buf = vim.api.nvim_get_current_buf()
    vim.bo[state.buf].buflisted = false
    vim.b[state.buf].terminal_panel = true
    vim.api.nvim_create_autocmd("TermClose", {
      buffer = state.buf,
      once = true,
      desc = "Shell exited: drop the panel so the next ␣t starts a fresh one",
      callback = function(ev)
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(ev.buf) then
            vim.api.nvim_buf_delete(ev.buf, { force = true })
          end
          state.buf, state.win = nil, nil
        end)
      end,
    })
  end

  local wo = vim.wo[state.win]
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "no"
  wo.winfixheight = true
end

function M.toggle()
  if M.is_open() then
    vim.api.nvim_win_hide(state.win)
    state.win = nil
    return
  end
  open()
  vim.cmd.startinsert()
end

-- Run a shell command line in the panel, opening it if needed, and keep the
-- cursor where it was.
function M.send(cmd)
  local from = vim.api.nvim_get_current_win()
  if not M.is_open() then
    open()
  end
  vim.fn.chansend(vim.bo[state.buf].channel, cmd .. "\r")
  vim.api.nvim_win_call(state.win, function()
    vim.cmd("normal! G")
  end)
  if vim.api.nvim_win_is_valid(from) and from ~= state.win then
    vim.api.nvim_set_current_win(from)
  end
end

-- A full-screen floating terminal running `cmd`; closes when
-- the program exits.
function M.float(cmd)
  local buf = vim.api.nvim_create_buf(false, true)
  local w = math.floor(vim.o.columns * 0.92)
  local h = math.floor(vim.o.lines * 0.9)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = w,
    height = h,
    col = math.floor((vim.o.columns - w) / 2),
    row = math.floor((vim.o.lines - h) / 2) - 1,
    border = "single",
    title = " " .. cmd .. " ",
    title_pos = "center",
  })
  vim.fn.jobstart(cmd, {
    term = true,
    on_exit = function()
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
        vim.cmd("checktime") -- pick up what the program changed on disk
      end)
    end,
  })
  vim.cmd.startinsert()
end

return M
