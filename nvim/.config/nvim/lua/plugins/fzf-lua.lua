-- The finder behind ␣␣ ␣/ ␣: ␣, and the ␣f group (config/keymaps.lua).
return {
  "ibhagwan/fzf-lua",
  cmd = "FzfLua",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  init = function()
    -- every "pick one" prompt (code actions, the debugger's configs, ...) in
    -- fzf too; fzf-lua itself only loads the first time one comes up
    vim.ui.select = function(...)
      require("fzf-lua").register_ui_select()
      return vim.ui.select(...)
    end
  end,
  opts = {
    -- fzf colors come from FZF_DEFAULT_OPTS (fish conf.d/00-colors.fish), same as the shell
    winopts = { border = "single", preview = { border = "single" } },
  },
}
