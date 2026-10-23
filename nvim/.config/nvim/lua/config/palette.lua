-- The fixed palette and the editor chrome it colors; loaded by config/theme.lua.
local colors = {
  black = "#0b0b0b",
  fg = "#d0d0d0",
  surface = "#161616",
  neon = "#bdbdbd",
  acid = "#e6e6e6",
  dim = "#2c2c2c",
  deep = "#1c1c1c",
  gray = "#5f5f5f",
  gray2 = "#858585",
  red = "#c46a6a",
  amber = "#c2a061",
  blue = "#7f93ad",
  magenta = "#a08aad",
  cyan = "#7fa8a3",
  white = "#f2f2f2",
}

local M = { colors = colors }

function M.setup()
  local hl = vim.api.nvim_set_hl
  local c = colors

  -- base editor surface
  hl(0, "Normal", { fg = c.fg, bg = c.black })
  hl(0, "NormalNC", { fg = c.fg, bg = c.black })
  hl(0, "NormalFloat", { fg = c.fg, bg = c.black })
  hl(0, "FloatBorder", { fg = c.neon, bg = c.black })
  hl(0, "FloatTitle", { fg = c.neon, bg = c.black, bold = true })
  -- Cursor is deliberately not themed — same white block cursor in every
  -- theme, so switching themes never needs to touch it (see apply-theme's
  -- git history for why: OSC 12 sync + tmux/kitty reload edge cases made a
  -- per-theme cursor color more trouble than it was worth).
  hl(0, "Cursor", { fg = c.black, bg = "#ffffff" })

  -- gutter / current line
  hl(0, "CursorLine", { bg = c.surface })
  hl(0, "CursorLineNr", { fg = c.neon, bold = true })
  hl(0, "LineNr", { fg = c.dim })
  hl(0, "SignColumn", { bg = c.black })
  hl(0, "ColorColumn", { bg = c.surface })
  hl(0, "NonText", { fg = c.dim })
  hl(0, "EndOfBuffer", { fg = c.dim })

  -- splits / status / tabs
  hl(0, "WinSeparator", { fg = c.dim, bg = c.black })
  hl(0, "VertSplit", { fg = c.dim, bg = c.black })
  hl(0, "StatusLine", { fg = c.neon, bg = c.black })
  hl(0, "StatusLineNC", { fg = c.gray, bg = c.black })
  hl(0, "WinBar", { fg = c.neon, bg = c.black, bold = true })
  hl(0, "WinBarNC", { fg = c.gray, bg = c.black })
  hl(0, "TabLine", { fg = c.gray2, bg = c.black })
  hl(0, "TabLineSel", { fg = c.black, bg = c.neon, bold = true })
  hl(0, "TabLineFill", { bg = c.black })

  -- popup menu (completion, cmdline palette, etc.)
  hl(0, "Pmenu", { fg = c.fg, bg = c.surface })
  hl(0, "PmenuSel", { fg = c.black, bg = c.neon, bold = true })
  hl(0, "PmenuSbar", { bg = c.dim })
  hl(0, "PmenuThumb", { bg = c.neon })

  -- selection / search
  hl(0, "Visual", { bg = c.dim })
  hl(0, "VisualNOS", { bg = c.deep })
  hl(0, "Search", { fg = c.black, bg = c.acid })
  hl(0, "IncSearch", { fg = c.black, bg = c.neon })
  hl(0, "CurSearch", { fg = c.black, bg = c.neon })
  hl(0, "MatchParen", { fg = c.black, bg = c.acid, bold = true })

  -- messages
  hl(0, "Title", { fg = c.neon, bold = true })
  hl(0, "Directory", { fg = c.acid })
  hl(0, "Question", { fg = c.neon })
  hl(0, "ModeMsg", { fg = c.neon })
  hl(0, "ErrorMsg", { fg = c.red, bold = true })
  hl(0, "WarningMsg", { fg = c.amber })

  -- gitsigns (sign-column indicators, not code)
  hl(0, "GitSignsAdd", { fg = c.neon })
  hl(0, "GitSignsChange", { fg = c.amber })
  hl(0, "GitSignsDelete", { fg = c.red })

  -- indent-blankline
  hl(0, "IblIndent", { fg = c.dim })
  hl(0, "IblScope", { fg = c.neon })

  -- which-key
  hl(0, "WhichKey", { fg = c.neon, bold = true })
  hl(0, "WhichKeyGroup", { fg = c.acid })
  hl(0, "WhichKeyDesc", { fg = c.fg })
  hl(0, "WhichKeySeparator", { fg = c.dim })
  hl(0, "WhichKeyBorder", { fg = c.neon, bg = c.black })
  hl(0, "WhichKeyFloat", { bg = c.black })

  -- neo-tree (project tree)
  hl(0, "NeoTreeNormal", { fg = c.fg, bg = c.black })
  hl(0, "NeoTreeNormalNC", { fg = c.fg, bg = c.black })
  hl(0, "NeoTreeWinSeparator", { fg = c.dim, bg = c.black })
  hl(0, "NeoTreeCursorLine", { bg = c.surface })
  hl(0, "NeoTreeRootName", { fg = c.neon, bold = true })
  hl(0, "NeoTreeDirectoryName", { fg = c.acid })
  hl(0, "NeoTreeDirectoryIcon", { fg = c.acid })
  hl(0, "NeoTreeFileName", { fg = c.fg })
  hl(0, "NeoTreeDotfile", { fg = c.gray })
  hl(0, "NeoTreeIndentMarker", { fg = c.dim })
  hl(0, "NeoTreeExpander", { fg = c.gray2 })
  hl(0, "NeoTreeTitleBar", { fg = c.black, bg = c.neon, bold = true })
  hl(0, "NeoTreeFloatBorder", { fg = c.neon, bg = c.black })
  hl(0, "NeoTreeGitAdded", { fg = c.neon })
  hl(0, "NeoTreeGitModified", { fg = c.amber })
  hl(0, "NeoTreeGitDeleted", { fg = c.red })
  hl(0, "NeoTreeGitUntracked", { fg = c.cyan })
  hl(0, "NeoTreeGitConflict", { fg = c.magenta, bold = true })
  hl(0, "NeoTreeGitIgnored", { fg = c.gray })

  -- aerial (outline)
  hl(0, "AerialNormal", { fg = c.fg, bg = c.black })
  hl(0, "AerialLine", { bg = c.surface, bold = true })
  hl(0, "AerialGuide", { fg = c.dim })

  -- trouble (problems panel)
  hl(0, "TroubleNormal", { fg = c.fg, bg = c.black })
  hl(0, "TroubleNormalNC", { fg = c.fg, bg = c.black })
  hl(0, "TroubleCount", { fg = c.black, bg = c.neon, bold = true })

  -- quickfix / diagnostics gutter
  hl(0, "QuickFixLine", { bg = c.surface, bold = true })
  hl(0, "qfFileName", { fg = c.acid })
  hl(0, "qfLineNr", { fg = c.gray2 })

  -- debugger signs and the stopped line
  hl(0, "DapBreakpoint", { fg = c.red })
  hl(0, "DapBreakpointCondition", { fg = c.amber })
  hl(0, "DapLogPoint", { fg = c.blue })
  hl(0, "DapBreakpointRejected", { fg = c.gray })
  hl(0, "DapStopped", { fg = c.neon, bold = true })
  hl(0, "DapStoppedLine", { bg = c.deep })
end

return M
