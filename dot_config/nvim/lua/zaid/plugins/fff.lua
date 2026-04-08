return {
	"dmtrKovalenko/fff.nvim",
	lazy = false,
	build = function()
		require("fff.download").download_or_build_binary()
	end,
	opts = {},
	keys = {
		{
			"<leader>ff",
			function()
				require("fff").find_files()
			end,
			desc = "fff: Find files",
		},
		{
			"<leader>fg",
			function()
				require("fff").live_grep()
			end,
			desc = "fff: Live grep",
		},
		{
			"<leader>fz",
			function()
				require("fff").live_grep({ grep = { modes = { "fuzzy", "plain" } } })
			end,
			desc = "fff: Fuzzy grep",
		},
		{
			"<leader>fc",
			function()
				require("fff").live_grep({ query = vim.fn.expand("<cword>") })
			end,
			desc = "fff: Grep current word",
		},
	},
}
