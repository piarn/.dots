return {
  "mfussenegger/nvim-lint",
  event = { "BufWritePost", "BufReadPost", "InsertLeave" },
  config = function()
    local lint = require("lint")

    lint.linters_by_ft = {
      go = { "golangcilint" },
      python = { "ruff" },
      sh = { "shellcheck" },
      yaml = { "yamllint" }, -- yamllint, if installed
    }

    vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
      callback = function()
        -- only the linters actually installed, so a machine without one
        -- (golangci-lint isn't in any extra) stays quiet instead of erroring
        local names = vim.tbl_filter(function(name)
          local linter = lint.linters[name]
          local cmd = type(linter) == "table" and linter.cmd
          if type(cmd) == "function" then
            cmd = cmd()
          end
          return type(cmd) == "string" and vim.fn.executable(cmd) == 1
        end, lint._resolve_linter_by_ft(vim.bo.filetype))
        if #names > 0 then
          lint.try_lint(names)
        end
      end,
    })
  end,
}
