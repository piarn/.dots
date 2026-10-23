-- Debugger: nvim-dap + nvim-dap-view (bottom panel that opens with a session
-- and closes after it). Keys are the ␣d group in config/keymaps.lua; ␣dd is
-- DEBUG mode (bare n/s/o/c/b/K until Esc).
--
-- Adapters come with the language toolchains, not mason, except debugpy:
--   go               dlv dap        (go install github.com/go-delve/delve/cmd/dlv@latest)
--   c/cpp/rust/zig   lldb-dap       (part of lldb)
--   python           debugpy        (mason; config/lsp.lua installs it)
return {
  "mfussenegger/nvim-dap",
  lazy = true,
  dependencies = {
    {
      "igorlfs/nvim-dap-view",
      opts = {
        auto_toggle = true, -- open on session start, close when it ends
        windows = { size = 0.3, position = "below" },
        winbar = {
          sections = { "scopes", "watches", "breakpoints", "threads", "repl", "console" },
          default_section = "scopes",
        },
        virtual_text = { enabled = true }, -- variable values inline, like Zed
      },
    },
  },
  config = function()
    local dap = require("dap")

    local sign = vim.fn.sign_define
    sign("DapBreakpoint", { text = "●", texthl = "DapBreakpoint" })
    sign("DapBreakpointCondition", { text = "◆", texthl = "DapBreakpointCondition" })
    sign("DapLogPoint", { text = "◇", texthl = "DapLogPoint" })
    sign("DapBreakpointRejected", { text = "○", texthl = "DapBreakpointRejected" })
    sign("DapStopped", { text = "▶", texthl = "DapStopped", linehl = "DapStoppedLine" })

    -- Go: delve speaks DAP itself.
    dap.adapters.go = {
      type = "server",
      port = "${port}",
      executable = { command = "dlv", args = { "dap", "-l", "127.0.0.1:${port}" } },
    }
    dap.configurations.go = {
      { type = "go", name = "Debug package", request = "launch", program = "${fileDirname}" },
      { type = "go", name = "Debug tests (package)", request = "launch", mode = "test", program = "${fileDirname}" },
      { type = "go", name = "Debug file", request = "launch", program = "${file}" },
    }

    -- C, C++, Rust, Zig: lldb-dap on a built binary.
    dap.adapters.lldb = { type = "executable", command = "lldb-dap", name = "lldb" }
    local function program()
      local guess = vim.fn.getcwd() .. "/"
      local cargo = vim.fn.getcwd() .. "/target/debug/" .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
      local zig = vim.fn.getcwd() .. "/zig-out/bin/" .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
      if vim.fn.executable(cargo) == 1 then
        guess = cargo
      elseif vim.fn.executable(zig) == 1 then
        guess = zig
      end
      return vim.fn.input("Program: ", guess, "file")
    end
    local native = {
      {
        type = "lldb",
        name = "Launch binary",
        request = "launch",
        program = program,
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
      },
    }
    for _, ft in ipairs({ "c", "cpp", "rust", "zig" }) do
      dap.configurations[ft] = native
    end

    -- Python: debugpy from mason; the debuggee runs in the project's venv if
    -- there is one.
    local debugpy = vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python"
    dap.adapters.python = { type = "executable", command = debugpy, args = { "-m", "debugpy.adapter" } }
    local function python()
      local venv = os.getenv("VIRTUAL_ENV")
      if venv then
        return venv .. "/bin/python"
      end
      for _, dir in ipairs({ ".venv", "venv" }) do
        local p = vim.fn.getcwd() .. "/" .. dir .. "/bin/python"
        if vim.fn.executable(p) == 1 then
          return p
        end
      end
      return "python3"
    end
    dap.configurations.python = {
      { type = "python", name = "Debug file", request = "launch", program = "${file}", pythonPath = python },
      { type = "python", name = "Debug pytest (file)", request = "launch", module = "pytest", args = { "${file}" }, pythonPath = python },
    }
  end,
}
