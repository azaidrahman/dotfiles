-- Standalone Neovim config for the Claude diff-review popup.
-- Launched via: nvim -u ~/.tmux/scripts/claude-diff-review-init.lua
-- Reuses the diffview/plenary already installed by lazy.nvim, but loads NONE
-- of the user's normal config, so it cannot interfere with it.

local data = vim.fn.stdpath("data")
vim.opt.rtp:prepend(data .. "/lazy/plenary.nvim")
vim.opt.rtp:prepend(data .. "/lazy/diffview.nvim")

vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.o.number = true
vim.o.signcolumn = "yes"
vim.o.termguicolors = true

local repo = vim.env.REPO
if repo and repo ~= "" then
  vim.cmd("cd " .. vim.fn.fnameescape(repo))
end

require("diffview").setup({})

-- Open the working-tree diff once the UI is ready. Guarded so that a headless
-- `nvim -u <this> +qa` (used for syntax-checking) does not try to open it.
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    if #vim.api.nvim_list_uis() > 0 then
      require("diffview").open()
    end
  end,
})
