return {
	"stevearc/aerial.nvim",
	cmd = "AerialToggle",
	keys = {
		{ "<leader>i", "<cmd>AerialToggle!<CR>", desc = "Toggle Aerial outline" },
	},
	opts = {},
	dependencies = {
		"nvim-treesitter/nvim-treesitter",
		"nvim-tree/nvim-web-devicons",
	},
}
