return {
    {
        "nvzone/showkeys",
        cmd = "ShowkeysToggle",
        event = "VeryLazy",
        keys = {
            { "<leader>sk", "<cmd>ShowkeysToggle<cr>", desc = "Toggle showkeys" },
        },
        config = function(_, opts)
            -- showkeys' internal redraw fires from a scheduled callback that can
            -- run after its float is closed, calling nvim_win_set_config with a
            -- nil/stale window handle and throwing "Invalid 'win'". Guard the
            -- public redraw so it no-ops once the window is gone.
            local utils, state = require("showkeys.utils"), require("showkeys.state")
            local orig_redraw = utils.redraw
            utils.redraw = function(...)
                if not state.win or not vim.api.nvim_win_is_valid(state.win) then
                    return
                end
                return orig_redraw(...)
            end
            require("showkeys").setup(opts)
            require("showkeys").toggle()
        end,
        opts = {
            -- "top-right" right-aligns the column but (unlike "bottom-*") leaves
            -- winopts.row untouched, so we hand-set row near the bottom but a few
            -- lines higher than the default (lines-5) to clear the noice mini
            -- notification stack in the bottom-right corner.
            position = "top-right",
            maxkeys = 3,
            show_count = true,
            excluded_modes = { "i" },
            winopts = {
                focusable = false,
                relative = "editor",
                style = "minimal",
                border = "single",
                height = 1,
                row = vim.o.lines - 10,
                col = 0,
            },
        },
    }
}
