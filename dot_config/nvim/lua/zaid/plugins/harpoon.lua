return {
	"thePrimeagen/harpoon",
	enabled = true,
	branch = "harpoon2",
	dependencies = {
		"nvim-lua/plenary.nvim",
	},
	config = function()
		local harpoon = require("harpoon")

		harpoon:setup({
			global_settings = {
				save_on_toggle = true,
				save_on_change = true,
			},
		})

		vim.keymap.set("n", "<leader>af", function()
			harpoon:list():add()
		end, { desc = "Harpoon add file" })
		vim.keymap.set("n", "<C-e>", function()
			harpoon.ui:toggle_quick_menu(harpoon:list())
		end, { desc = "Harpoon quick menu" })

		vim.keymap.set("n", "<leader>ap", function()
			harpoon:list():prev({ ui_nav_wrap = true })
		end, { desc = "Harpoon prev" })
		vim.keymap.set("n", "<leader>an", function()
			harpoon:list():next({ ui_nav_wrap = true })
		end, { desc = "Harpoon next" })
		vim.keymap.set("n", "[a", function()
			harpoon:list():prev({ ui_nav_wrap = true })
		end, { desc = "Harpoon prev" })
		vim.keymap.set("n", "]a", function()
			harpoon:list():next({ ui_nav_wrap = true })
		end, { desc = "Harpoon next" })
	end,
}
