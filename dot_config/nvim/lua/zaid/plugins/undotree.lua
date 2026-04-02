-- NOTE: Neovim 0.12 ships a built-in undo tree visualizer (:Undotree)
-- This replaces the mbbill/undotree plugin. packadd loads the opt-in built-in package.
-- See :h undotree for usage
vim.cmd.packadd("nvim.undotree")
vim.keymap.set("n", "<leader>u", "<cmd>Undotree<CR>", { desc = "Toggle undo tree", noremap = true, silent = true })

-- return empty spec so lazy.nvim doesn't try to install anything
return {}
