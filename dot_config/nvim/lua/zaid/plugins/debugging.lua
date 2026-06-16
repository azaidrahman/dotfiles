return {
    "mfussenegger/nvim-dap",
    -- Lazy-loaded: nothing is pulled in until you press a <Leader>d… key.
    keys = {
        { "<Leader>db", function() require("dap").toggle_breakpoint() end, desc = "DAP: Toggle breakpoint" },
        { "<Leader>dc", function() require("dap").continue() end, desc = "DAP: Continue / start" },
        { "<Leader>do", function() require("dap").step_over() end, desc = "DAP: Step over" },
        { "<Leader>di", function() require("dap").step_into() end, desc = "DAP: Step into" },
        { "<Leader>dO", function() require("dap").step_out() end, desc = "DAP: Step out" },
        { "<Leader>dt", function() require("dapui").toggle() end, desc = "DAP: Toggle UI" },
        { "<Leader>dT", function() require("dap-go").debug_test() end, desc = "DAP: Debug nearest test" },
        { "<Leader>de", function() require("dapui").eval(nil, { enter = true }) end, desc = "DAP: Evaluate expression" },
    },
    dependencies = {
        "nvim-neotest/nvim-nio",
        "rcarriga/nvim-dap-ui",
        "leoluz/nvim-dap-go",
    },

    config = function()
        local dap = require("dap")
        local dapui = require("dapui")

        require("dap-go").setup()
        require("dapui").setup()

        -- Clear, colored gutter signs (defaults are a dim "B" that's easy to miss).
        vim.api.nvim_set_hl(0, "DapBreakpointHl", { fg = "#e51400" })
        vim.api.nvim_set_hl(0, "DapStoppedHl", { fg = "#ffcc00" })
        vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DapBreakpointHl" })
        vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DapBreakpointHl" })
        vim.fn.sign_define("DapLogPoint", { text = "◆", texthl = "DapBreakpointHl" })
        vim.fn.sign_define("DapStopped", { text = "→", texthl = "DapStoppedHl", linehl = "Visual" })

        dap.listeners.before.attach.dapui_config = function()
            dapui.open()
        end
        dap.listeners.before.launch.dapui_config = function()
            dapui.open()
        end
        dap.listeners.before.event_terminated.dapui_config = function()
            dapui.close()
        end
        dap.listeners.before.event_exited.dapui_config = function()
            dapui.close()
        end
    end,
}
