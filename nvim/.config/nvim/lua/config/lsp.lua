-- LSP behavior: server settings, servers from the toolchains,
-- diagnostics look, and the non-LSP tools mason keeps installed. Keys for all
-- of this are in config/keymaps.lua.
local M = {}

-- Installed with their toolchain (distro package, mise, go install), not
-- mason. Enabled only when the binary is on PATH, so a machine without that
-- toolchain stays quiet.
local from_toolchains = { "gopls", "clangd", "rust_analyzer", "nim_langserver" }

-- Formatters conform.nvim calls and the Python debug adapter.
local tools = { "debugpy", "stylua", "shfmt", "goimports", "gofumpt" }

local function ensure_tools()
  local ok, registry = pcall(require, "mason-registry")
  if not ok then
    return
  end
  registry.refresh(function()
    for _, name in ipairs(tools) do
      local found, pkg = pcall(registry.get_package, name)
      if found and not pkg:is_installed() then
        pkg:install()
      end
    end
  end)
end

function M.setup()
  -- lua_ls: recognize the vim global so config files don't warn
  vim.lsp.config("lua_ls", {
    settings = {
      Lua = {
        diagnostics = { globals = { "vim" } },
        hint = { enable = true },
      },
    },
  })

  -- ruff: use for linting/actions, defer formatting to conform.nvim
  vim.lsp.config("ruff", {
    init_options = {
      settings = { organizeImports = true },
    },
  })

  -- jsonls/yamlls: schemas from SchemaStore (package.json, tsconfig,
  -- GitHub workflows, compose files, ...), picked by file name
  vim.lsp.config("jsonls", {
    settings = {
      json = {
        schemas = require("schemastore").json.schemas(),
        validate = { enable = true },
      },
    },
  })

  vim.lsp.config("yamlls", {
    settings = {
      yaml = {
        -- yamlls' built-in store is off so SchemaStore.nvim's list is the only one
        schemaStore = { enable = false, url = "" },
        schemas = require("schemastore").yaml.schemas(),
        keyOrdering = false,
      },
    },
  })

  vim.lsp.config("gopls", {
    settings = {
      gopls = {
        hints = {
          assignVariableTypes = true,
          compositeLiteralFields = true,
          parameterNames = true,
          rangeVariableTypes = true,
        },
      },
    },
  })

  for _, name in ipairs(from_toolchains) do
    local cfg = vim.lsp.config[name]
    local cmd = cfg and cfg.cmd
    if type(cmd) == "table" and vim.fn.executable(cmd[1]) == 1 then
      vim.lsp.enable(name)
    end
  end

  vim.diagnostic.config({
    virtual_text = { spacing = 2, prefix = "●" },
    severity_sort = true,
    float = { border = "single", source = true },
    signs = {
      text = {
        [vim.diagnostic.severity.ERROR] = "●",
        [vim.diagnostic.severity.WARN] = "▲",
        [vim.diagnostic.severity.INFO] = "◆",
        [vim.diagnostic.severity.HINT] = "·",
      },
    },
  })

  ensure_tools()
end

return M
