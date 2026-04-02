return{
    "mfussenegger/nvim-dap",
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

        vim.keymap.set("n", "<Leader>db", dap.toggle_breakpoint, { desc = "Toggle breakpoint" })
        vim.keymap.set("n", "<Leader>dc", dap.continue, { desc = "Continue" })
        vim.keymap.set("n", "<Leader>do", dap.step_over, { desc = "Step over" })
        vim.keymap.set("n", "<Leader>di", dap.step_into, { desc = "Step into" })
        vim.keymap.set("n", "<Leader>dO", dap.step_out, { desc = "Step out" })
        vim.keymap.set("n", "<Leader>dt", dapui.toggle, { desc = "Toggle DAP UI" })
        vim.keymap.set("n", "<Leader>de", function()
            -- nvim-dap-ui evaluate expression under cursor
            dapui.eval(nil, { enter = true })
        end, { desc = "DAP evaluate expression" })
    end,
}
