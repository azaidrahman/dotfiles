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

local function list_lines()
  if #M.collected == 0 then
    return { "(nothing collected)" }
  end
  return vim.deepcopy(M.collected)
end

function M.refresh_list()
  if M.list_buf and vim.api.nvim_buf_is_valid(M.list_buf) then
    vim.bo[M.list_buf].modifiable = true
    vim.api.nvim_buf_set_lines(M.list_buf, 0, -1, false, list_lines())
    vim.bo[M.list_buf].modifiable = false
  end
end

-- Jump to a collected ref's file+line within the open diffview.
function M.jump_to(ref)
  local path, s = ref:match("^(.-):(%d+)%-")
  if not path then
    return
  end
  s = tonumber(s)
  if M.list_win and vim.api.nvim_win_is_valid(M.list_win) then
    vim.api.nvim_win_close(M.list_win, true)
    M.list_win = nil
  end
  local ok, lib = pcall(require, "diffview.lib")
  if not ok then
    return
  end
  local view = lib.get_current_view()
  if not (view and view.panel) then
    return
  end
  for _, f in ipairs(view.panel:ordered_file_list()) do
    if f.path == path then
      view:set_file(f, false, true)
      vim.schedule(function()
        pcall(vim.fn.cursor, s, 1)
      end)
      return
    end
  end
end

function M.toggle_list()
  if M.list_win and vim.api.nvim_win_is_valid(M.list_win) then
    vim.api.nvim_win_close(M.list_win, true)
    M.list_win = nil
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  M.list_buf = buf
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, list_lines())
  vim.bo[buf].modifiable = false
  local width = 60
  M.list_win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    anchor = "NE",
    row = 1,
    col = vim.o.columns - 1,
    width = width,
    height = math.max(1, #M.collected),
    style = "minimal",
    border = "rounded",
    title = " collected ",
  })
  vim.keymap.set("n", "dd", function()
    local idx = vim.fn.line(".")
    if M.collected[idx] then
      table.remove(M.collected, idx)
      M.refresh_list()
      if M.list_win and vim.api.nvim_win_is_valid(M.list_win) then
        vim.api.nvim_win_set_height(M.list_win, math.max(1, #M.collected))
      end
    end
  end, { buffer = buf, desc = "remove collected ref" })
  vim.keymap.set("n", "q", function()
    M.toggle_list()
  end, { buffer = buf, desc = "close list" })
  vim.keymap.set("n", "<CR>", function()
    local idx = vim.fn.line(".")
    if M.collected[idx] then
      M.jump_to(M.collected[idx])
    end
  end, { buffer = buf, desc = "jump to ref" })
end

function M.confirm()
  if #M.collected == 0 then
    vim.notify("nothing collected", vim.log.levels.WARN)
    return
  end
  local pane = vim.env.CLAUDE_PANE
  local refs = table.concat(M.collected, " ") -- single line: no submit risk
  if pane and pane ~= "" then
    vim.fn.system({ "tmux", "send-keys", "-t", pane, "-l", refs })
  end
  vim.cmd("qa!")
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
vim.keymap.set("n", "<leader>l", M.toggle_list, { desc = "toggle collected list" })
vim.keymap.set("n", "<leader><CR>", M.confirm, { desc = "confirm & paste refs to Claude" })
vim.keymap.set("n", "q", function() vim.cmd("qa!") end, { desc = "bail (send nothing)" })

vim.api.nvim_create_autocmd("BufWinEnter", {
  callback = function(ev)
    local ft = vim.bo[ev.buf].filetype or ""
    if ft:match("^Diffview") then
      vim.keymap.set("n", "q", function() vim.cmd("qa!") end,
        { buffer = ev.buf, desc = "bail (send nothing)" })
    end
  end,
})

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
