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
            position = "bottom-right",
            maxkeys = 3,
            show_count = true,
            winopts = {
                focusable = false,
                relative = "editor",
                style = "minimal",
                border = "single",
                height = 1,
                row = 1,
                col = 0,
            },
        },
    }
}
