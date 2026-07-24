-- Close the quickfix / location list window with `q`.
-- <leader>qg (overseer run) opens output here via on_output_quickfix.
vim.keymap.set("n", "q", "<cmd>cclose<CR>", { buffer = true, silent = true, desc = "Close quickfix" })
