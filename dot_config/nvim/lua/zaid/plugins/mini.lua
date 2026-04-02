return {
	-- NOTE: Context-aware commenting for embedded languages (Vue, JSX/TSX, etc)
	-- Neovim 0.10+ has native gc/gcc commenting, so mini.comment is no longer needed.
	-- This plugin hooks into the native gc operator to pick the right commentstring
	-- based on treesitter context (e.g. JS vs HTML sections in a .vue file)
	{
		"JoosepAlviste/nvim-ts-context-commentstring",
		event = "VeryLazy",
		config = function()
			require("ts_context_commentstring").setup({
				enable_autocmd = false,
			})

			-- Hook ts-context-commentstring into the native gc operator
			-- This overrides how Neovim resolves commentstring so it uses treesitter context
			local get_option = vim.filetype.get_option
			---@diagnostic disable-next-line: duplicate-set-field
			vim.filetype.get_option = function(filetype, option)
				return option == "commentstring"
						and require("ts_context_commentstring.internal").calculate_commentstring()
					or get_option(filetype, option)
			end
		end,
	},
	-- Surround
	{
		"echasnovski/mini.surround",
		event = { "BufReadPre", "BufNewFile" },
		opts = {
			custom_surroundings = nil,
			highlight_duration = 300,
			mappings = {
				add = "sa",
				delete = "ds",
				find = "sf",
				find_left = "sF",
				highlight = "sh",
				replace = "sr",
				update_n_lines = "sn",
				suffix_last = "l",
				suffix_next = "n",
			},
			n_lines = 20,
			respect_selection_type = false,
			search_method = "cover",
			space_pad = false,
			silent = false,
		},
	},
	-- Get rid of whitespace
	{
		"echasnovski/mini.trailspace",
		event = { "BufReadPost", "BufNewFile" },
		config = function()
			local miniTrailspace = require("mini.trailspace")

			miniTrailspace.setup({
				only_in_normal_buffers = true,
			})
			vim.keymap.set("n", "<leader>cw", function()
				miniTrailspace.trim()
			end, { desc = "Erase Whitespace" })

			vim.api.nvim_create_autocmd("CursorHold", {
				pattern = "*",
				callback = function()
					require("mini.trailspace").unhighlight()
				end,
			})
		end,
	},
	-- Split & join
	{
		"echasnovski/mini.splitjoin",
		keys = {
			{
				"sj",
				function()
					require("mini.splitjoin").join()
				end,
				mode = { "n", "x" },
				desc = "Join arguments",
			},
			{
				"sk",
				function()
					require("mini.splitjoin").split()
				end,
				mode = { "n", "x" },
				desc = "Split arguments",
			},
		},
		config = function()
			require("mini.splitjoin").setup({
				mappings = { toggle = "" },
			})
		end,
	},
}
