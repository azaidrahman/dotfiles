return {
	-- Comments
	{
		"echasnovski/mini.comment",
		version = false,
		event = "VeryLazy",
		dependencies = {
			"JoosepAlviste/nvim-ts-context-commentstring",
		},
		config = function()
			require("ts_context_commentstring").setup({
				enable_autocmd = false,
			})

			require("mini.comment").setup({
				options = {
					custom_commentstring = function()
						return require("ts_context_commentstring.internal").calculate_commentstring({
							key = "commentstring",
						}) or vim.bo.commentstring
					end,
				},
			})
		end,
	},
	-- File explorer (this works properly with oil unlike nvim-tree)
	{
		"echasnovski/mini.files",
		keys = {
			{
				"<leader>ee",
				function()
					require("mini.files").open()
				end,
				desc = "Toggle mini file explorer",
			},
			{
				"<leader>ef",
				function()
					local MiniFiles = require("mini.files")
					MiniFiles.open(vim.api.nvim_buf_get_name(0), false)
					MiniFiles.reveal_cwd()
				end,
				desc = "Toggle into currently opened file",
			},
		},
		config = function()
			require("mini.files").setup({
				mappings = {
					go_in = "<CR>",
					go_in_plus = "L",
					go_out = "-",
					go_out_plus = "H",
				},
			})
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

			vim.api.nvim_create_autocmd("CursorMoved", {
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
