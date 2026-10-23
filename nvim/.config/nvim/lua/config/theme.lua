-- Editor chrome only (statusline, splits, popups, gutter, signs); code
-- syntax colors are untouched. The palette and the highlight groups it sets
-- are in config/palette.lua.
local M = {}

local function load()
  local ok, palette = pcall(require, "config.palette")
  if ok and type(palette) == "table" then
    return palette
  end
end

function M.colors()
  local palette = load()
  return palette and palette.colors or {}
end

-- lualine theme from the palette: the mode block carries the mode's color,
-- the rest sits on the background like tmux's status bar.
function M.lualine()
  local c = M.colors()
  local function mode(color)
    return {
      a = { fg = c.black, bg = color, gui = "bold" },
      b = { fg = c.fg, bg = c.surface },
      c = { fg = c.gray2, bg = c.black },
    }
  end
  return {
    normal = mode(c.neon),
    insert = mode(c.acid),
    visual = mode(c.magenta),
    replace = mode(c.red),
    command = mode(c.amber),
    terminal = mode(c.cyan),
    inactive = {
      a = { fg = c.gray, bg = c.black },
      b = { fg = c.gray, bg = c.black },
      c = { fg = c.gray, bg = c.black },
    },
  }
end

-- bufferline's `highlights` option: selected buffer in the accent, the rest dim.
function M.bufferline()
  local c = M.colors()
  local bg = { bg = c.black }
  local sel = { fg = c.neon, bg = c.surface, bold = true, italic = false }
  return {
    fill = bg,
    background = { fg = c.gray, bg = c.black },
    buffer_visible = { fg = c.gray2, bg = c.black },
    buffer_selected = sel,
    separator = { fg = c.dim, bg = c.black },
    separator_visible = { fg = c.dim, bg = c.black },
    separator_selected = { fg = c.dim, bg = c.surface },
    indicator_selected = { fg = c.neon, bg = c.surface },
    modified = { fg = c.amber, bg = c.black },
    modified_visible = { fg = c.amber, bg = c.black },
    modified_selected = { fg = c.amber, bg = c.surface },
    duplicate = { fg = c.gray, bg = c.black, italic = true },
    duplicate_selected = { fg = c.gray2, bg = c.surface, italic = true },
    error = { fg = c.gray, bg = c.black },
    error_selected = { fg = c.red, bg = c.surface, bold = true },
    error_diagnostic = { fg = c.red, bg = c.black },
    error_diagnostic_selected = { fg = c.red, bg = c.surface },
    warning = { fg = c.gray, bg = c.black },
    warning_selected = { fg = c.amber, bg = c.surface, bold = true },
    warning_diagnostic = { fg = c.amber, bg = c.black },
    warning_diagnostic_selected = { fg = c.amber, bg = c.surface },
    offset_separator = { fg = c.dim, bg = c.black },
  }
end

local function apply()
  local theme = load()
  if theme and theme.setup then
    theme.setup()
  end
end

apply()

vim.api.nvim_create_autocmd("ColorScheme", {
  desc = "Reapply the palette on top of any colorscheme change",
  callback = apply,
})

-- The Cursor highlight group above makes nvim push its color into the
-- terminal via OSC 12 while running. Without this, that color stays latched
-- in the pty after nvim quits and wins over kitty/foot's own cursor color
-- (both explicitly say a program-set cursor color takes precedence over
-- their own config) — so a shell that's had nvim open in it keeps showing
-- a stale cursor color until the escape code is reset. OSC 112 is the "reset cursor color to terminal default" sequence.
vim.api.nvim_create_autocmd("VimLeave", {
  desc = "Release the OSC 12 cursor color back to the terminal on exit",
  callback = function()
    io.write("\27]112\7")
    io.flush()
  end,
})

return M
