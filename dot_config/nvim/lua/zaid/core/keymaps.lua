local yank = require 'zaid.core.yank'
local opts = { noremap = true, silent = true }
-- noremap just means that the keymap stops at that trigger and doesnt get retriggered, or in other words, it doesnt get overridden
local descopts = function(desc)
    return {noremap=true,silent=true,desc=desc}
end
vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "moves lines down in visual selection" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "moves lines up in visual selection" })

vim.keymap.set("n", "J", "mzJ`z", { desc = "Join lines (cursor stays)" })
vim.keymap.set("n", "<C-d>", "<C-d>zz", { desc = "move down in buffer with cursor centered" })
vim.keymap.set("n", "<C-u>", "<C-u>zz", { desc = "move up in buffer with cursor centered" })
vim.keymap.set("n", "n", "nzzzv", { desc = "Next search result (centered)" })
vim.keymap.set("n", "N", "Nzzzv", { desc = "Prev search result (centered)" })

vim.keymap.set("v", "<", "<gv", opts)
vim.keymap.set("v", ">", ">gv", opts)

vim.keymap.set("n", "<leader>bv","ggVG", descopts("Select all in buffer") )

vim.keymap.set("n", "<leader>bd", "<cmd>BDelete this<CR>", descopts("[B]uffer [D]elete"))
vim.keymap.set("n", "<leader>bo", "<cmd>BDelete other<CR>", descopts("[B]uffer [O]ther"))
vim.keymap.set("n", "<leader>bn", "<cmd>BDelete nameless<CR>", descopts("[B]uffer [N]ameless"))

vim.keymap.set("n", "<leader>qq", ":q<CR>", opts)
vim.keymap.set("n", "<leader>qc", ":q!<CR>", opts)
vim.keymap.set("n", "<leader>qw", ":w<CR>", opts)

vim.keymap.set("n", "<leader>pd", function() Snacks.dashboard() end, descopts("Open dashboard"))

-- remember yanked
vim.keymap.set("v", "p", '"_dp', opts)

-- Copies or Yank to system clipboard
vim.keymap.set("n", "<leader>yy", [["+Y]], { desc = "Yank line to system clipboard" })

-- yank path
vim.keymap.set('n', '<leader>ya', function()
  yank.yank_path(yank.get_buffer_absolute(), 'absolute')
end, { desc = '[Y]ank [A]bsolute path to clipboard' })

vim.keymap.set('n', '<C-g>', function()
  local path = vim.bo.filetype == 'oil'
    and require('oil').get_current_dir()
    or yank.get_buffer_absolute()

  vim.cmd('file')              -- native <C-g> output
  vim.fn.setreg('+', path)
  vim.notify(path, vim.log.levels.INFO, { title = 'Yanked path' })
end, { desc = 'Show + yank current buffer/oil path' })

vim.keymap.set('n', '<leader>yr', function()
  yank.yank_path(yank.get_buffer_cwd_relative(), 'relative')
end, { desc = '[Y]ank [R]elative path to clipboard' })

vim.keymap.set('v', '<leader>ya', function()
  yank.yank_visual_with_path(yank.get_buffer_absolute(), 'absolute')
end, { desc = '[Y]ank selection with [A]bsolute path' })

vim.keymap.set('v', '<leader>yr', function()
  yank.yank_visual_with_path(yank.get_buffer_cwd_relative(), 'relative')
end, { desc = '[Y]ank selection with [R]elative path' })

vim.keymap.set("n", "<Esc>", ":nohl<CR>", { desc = "Clear search hl", silent = true })

-- Disable <Esc> to build the habit of using <C-c> to escape
vim.keymap.set("i", "<Esc>", "<nop>", { desc = "Disabled — use <C-c>" })
vim.keymap.set("v", "<Esc>", "<nop>", { desc = "Disabled — use <C-c>" })
vim.keymap.set("s", "<Esc>", "<nop>", { desc = "Disabled — use <C-c>" })

-- Unmaps Q in normal mode
vim.keymap.set("n", "Q", "<nop>", { desc = "Disabled" })

-- prevent x delete from registering when next paste
vim.keymap.set("n", "x", '"_x', { desc = "Delete char (no register)" })

-- tab stuff (standalone only — tmux windows are the workspace unit inside tmux)
require("zaid.core.env").when_standalone(function()
    vim.keymap.set("n", "<leader>to", "<cmd>tabnew<CR>", { desc = "Open new tab" })
    vim.keymap.set("n", "<leader>tx", "<cmd>tabclose<CR>", { desc = "Close current tab" })
    vim.keymap.set("n", "<leader>tn", "<cmd>tabn<CR>", { desc = "Go to next tab" })
    vim.keymap.set("n", "<leader>tp", "<cmd>tabp<CR>", { desc = "Go to previous tab" })
    vim.keymap.set("n", "<leader>tf", "<cmd>tabnew %<CR>", { desc = "Open current buffer in new tab" })
end)

-- buffer stuff
vim.keymap.set("n", "<S-l>", ":bnext<CR>", { noremap = true, silent = true, desc = "Move to next buffer" })
vim.keymap.set("n", "<S-h>", ":bprevious<CR>", { noremap = true, silent = true, desc = "Move to previous buffer" })

-- get current buffers directory
vim.keymap.set("n", "<leader>hd", function()
    print(vim.fn.expand("%:p:h"))
end, descopts("Show current buffer directory")
)


vim.keymap.set("v", "<leader>hs", function()
    vim.cmd('normal! "xy')
    vim.cmd('execute "help " . @x')
end, { noremap = true, silent = true, desc = "Search under cursor in help" })

-- Toggle LSP diagnostics visibility (starts false to match lspconfig's virtual_text = false)
local isLspDiagnosticsVisible = false
vim.keymap.set("n", "<leader>lx", function()
	isLspDiagnosticsVisible = not isLspDiagnosticsVisible
	vim.diagnostic.config({
		virtual_text = isLspDiagnosticsVisible,
		underline = isLspDiagnosticsVisible,
	})
end, { desc = "Toggle LSP diagnostics" })

vim.keymap.set("n", "<leader>qr","<cmd>make<cr>", descopts("Run makefile") )

vim.keymap.set("n", "<leader>pq", "<cmd>copen<CR>", descopts("Open quickfix list") )

vim.keymap.set("n","<leader>gn","<cmd>Neogit<cr>",descopts("Open neogit"))

vim.keymap.set("n", "<leader>hm", "<cmd>Noice history<cr>", descopts("[H]istory of [M]essages (noice)"))


