-- Server installs + lspconfig's server definitions. What the servers do once
-- attached (settings, diagnostics, toolchain servers) is config/lsp.lua; their
-- keys are config/keymaps.lua.
return {
  {
    "mason-org/mason.nvim",
    opts = {},
  },
  {
    "mason-org/mason-lspconfig.nvim",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "mason-org/mason.nvim",
      "neovim/nvim-lspconfig",
      "b0o/SchemaStore.nvim", -- JSON/YAML schemas for jsonls and yamlls
    },
    -- Only servers no language extra installs; gopls, clangd, rust_analyzer
    -- and nim_langserver come with their toolchains (see config/lsp.lua).
    opts = {
      ensure_installed = {
        "basedpyright",
        "ruff",
        "lua_ls",
        "bashls",
        "yamlls",
        "jsonls",
        "ts_ls",
        "zls",
        "dockerls",
        "docker_compose_language_service",
      },
    },
    config = function(_, opts)
      require("config.lsp").setup()
      require("mason-lspconfig").setup(opts)
    end,
  },
}
