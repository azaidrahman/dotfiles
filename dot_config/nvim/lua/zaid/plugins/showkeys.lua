return {
    {
        "nvzone/showkeys",
        cmd = "ShowkeysToggle",
        event = "VeryLazy",
        keys = {
            { "<leader>sk", "<cmd>ShowkeysToggle<cr>", desc = "Toggle showkeys" },
        },
        config = function(_, opts)
            require("showkeys").setup(opts)

            -- Durable guard against an upstream race: the timer-driven
            -- clear_and_close and the WinClosed/TabEnter autocmds can run after
            -- the float's window id is already invalid, so redraw() ->
            -- update_win_w() -> nvim_win_set_config() throws. We can't patch the
            -- plugin's `local update_win_w` directly, but we can wrap its public
            -- entry points to no-op / reset cleanly when state.win is dead.
            local utils = require("showkeys.utils")
            local state = require("showkeys.state")
            local win_dead = function()
                return state.win and not vim.api.nvim_win_is_valid(state.win)
            end

            local orig_redraw = utils.redraw
            utils.redraw = function(...)
                if win_dead() then
                    return
                end
                return orig_redraw(...)
            end

            local orig_clear_and_close = utils.clear_and_close
            utils.clear_and_close = function(...)
                if win_dead() then
                    state.keys = {}
                    state.win = nil
                    return
                end
                return orig_clear_and_close(...)
            end

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
