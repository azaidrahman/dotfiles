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

-- ── collection state ──────────────────────────────────────────────────────
local M = { collected = {} }

-- The HEAD/left side of a diffview is a `diffview://` git-blob URI; the
-- working-tree side is the real file on disk. Only the latter has line numbers
-- that match the actual file, so collection is restricted to it.
local function is_worktree_side()
  local name = vim.api.nvim_buf_get_name(0)
  if name == "" or name:match("^diffview://") then
    return false
  end
  return vim.fn.filereadable(name) == 1
end

-- Path of the current buffer, relative to the repo (cwd was set to REPO).
local function rel_path()
  return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":.")
end

-- Find the changed-hunk line range (in the new/working file) containing `line`,
-- by parsing `git diff -U0 HEAD` for the current file (HEAD, to match what
-- diffview.open() shows: working tree vs HEAD, incl. staged changes).
-- Returns start,stop or nil.
local function hunk_range_at(line)
  local file = vim.api.nvim_buf_get_name(0)
  local out = vim.fn.systemlist({ "git", "diff", "-U0", "HEAD", "--", file })
  for _, l in ipairs(out) do
    local c, d = l:match("^@@ %-%d+,?%d* %+(%d+),?(%d*) @@")
    if c then
      c = tonumber(c)
      d = (d ~= "" and tonumber(d)) or 1
      if d == 0 then d = 1 end -- pure-deletion hunk: anchor on one line
      local s, e = c, c + d - 1
      if line >= s and line <= e then
        return s, e
      end
    end
  end
  return nil
end

local function add_ref(s, e)
  local ref = rel_path() .. ":" .. s .. "-" .. e
  table.insert(M.collected, ref)
  vim.notify("+ collected (" .. #M.collected .. "): " .. ref)
end

function M.collect_hunk()
  if not is_worktree_side() then
    vim.notify("select in the current-file side", vim.log.levels.WARN)
    return
  end
  local s, e = hunk_range_at(vim.fn.line("."))
  if not s then
    vim.notify("no changed hunk under cursor", vim.log.levels.WARN)
    return
  end
  add_ref(s, e)
end

function M.collect_visual()
  if not is_worktree_side() then
    vim.notify("select in the current-file side", vim.log.levels.WARN)
    return
  end
  local s, e = vim.fn.line("v"), vim.fn.line(".")
  if s > e then
    s, e = e, s
  end
  add_ref(s, e)
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
end

vim.keymap.set("n", "<leader>a", M.collect_hunk, { desc = "collect hunk under cursor" })
vim.keymap.set("x", "<leader>a", M.collect_visual, { desc = "collect visual selection" })

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
