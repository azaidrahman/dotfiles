return {
    {
        "roobert/tailwindcss-colorizer-cmp.nvim",
        config = function()
            require("tailwindcss-colorizer-cmp").setup({
                color_square_width = 2,
            })
        end,
    },
    {
        "NvChad/nvim-colorizer.lua",
        dependencies = { "nvim-treesitter/nvim-treesitter" },
        config = function()
            require("colorizer").setup({
                user_default_options = {
                    rgb_fn = true,
                    RRGGBBAA = true,
                    tailwind = true,
                },
                filetypes = { "html", "css", "javascript", "typescript", "jsx", "tsx", "vue", "svelte" },
            })
        end,
    },
}
