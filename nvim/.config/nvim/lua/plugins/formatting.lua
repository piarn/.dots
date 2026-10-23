return {
  "stevearc/conform.nvim",
  cmd = { "ConformInfo" },
  opts = {
    -- format-on-save is off entirely; ␣cf runs one of these on demand.
    formatters_by_ft = {
      go = { "goimports", "gofumpt" },
      python = { "ruff_format" },
      lua = { "stylua" },
      c = { "clang_format" },
      rust = { "rustfmt" },
      nim = { "nimpretty" },
      sh = { "shfmt" },
      json = { "jq" }, -- jq, if installed
      yaml = { "yq" }, -- yq, if installed
    },
  },
}
