return {
	"stevearc/oil.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	keys = {
		{ "-", "<CMD>Oil<CR>", desc = "Open parent directory" },
		{
			"<leader>-",
			function()
				require("oil").toggle_float()
			end,
			desc = "Open parent directory (float)",
		},
	},
	config = function()
		require("oil").setup({
			win_options = {
				signcolumn = "yes:2",
			},
			default_file_explorer = true,
			columns = {
				"icon",
				"permissions",
				"size",
				"mtime",
			},
			keymaps = {
				["<C-h>"] = false,
				["<C-c>"] = false,
				["<C-l>"] = false,
				["<M-h>"] = "actions.select_split",
				["q"] = "actions.close",
				["gy"] = {
					desc = "Yank entry path to clipboard",
					callback = function()
						local oil = require("oil")
						local entry = oil.get_cursor_entry()
						local dir = oil.get_current_dir()
						if not entry or not dir then
							return
						end
						local name = entry.name
						if entry.type == "directory" then
							name = name .. "/"
						end
						local path = dir .. name
						vim.fn.setreg("+", path)
						vim.notify(path, vim.log.levels.INFO, { title = "Yanked path" })
					end,
				},
			},
			delete_to_trash = true,
			view_options = {
				show_hidden = true,
			},
			skip_confirm_for_simple_edits = true,
		})

		vim.api.nvim_create_autocmd("FileType", {
			pattern = "oil",
			callback = function()
				vim.opt_local.cursorline = true
			end,
		})
	end,
}
