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
                row = vim.o.lines - 5,
                col = 0,
            },
        },
    }
}
