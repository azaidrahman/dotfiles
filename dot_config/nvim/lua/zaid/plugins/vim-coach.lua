return {
	"shahshlok/vim-coach.nvim",
	dependencies = {
		"nvim-telescope/telescope.nvim",
		"nvim-lua/plenary.nvim",
	},
	config = function()
		require("vim-coach").setup()
	end,
	keys = {
		{ "<leader>?", "<cmd>VimCoach<cr>", desc = "Vim Coach" },
	},
}
