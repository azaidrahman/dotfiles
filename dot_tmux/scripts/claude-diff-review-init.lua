-- Standalone Neovim config for the Claude diff-review popup.
-- Launched via: nvim -u ~/.tmux/scripts/claude-diff-review-init.lua
-- (tmux prefix+e → ~/.tmux/scripts/claude-diff-review.sh → this popup).
-- Reuses codediff.nvim (installed by lazy.nvim), but loads NONE
-- of the user's normal config, so it cannot interfere with it.
--
-- KEYS (leader = Space) — press <leader>? in the popup for this list:
--   <leader>a       collect hunk under cursor (normal) / selection (visual)
--                   — working-tree (right) side only
--   <leader>l       toggle collected list  (dd remove · <CR> jump · q close)
--   <leader>z       jump to another git repo (zoxide picker)
--   <leader><CR>    confirm: paste refs to the origin pane (errors if not Claude)
--   q  /  :q        bail — quit, send nothing
--   <leader>?       show this cheatsheet
-- codediff nav: ]f/[f or <Tab>/<S-Tab> next/prev file · <CR> open from explorer
--   <C-h/j/k/l> move between windows · ]c/[c hunk · <C-f>/<C-b> scroll
--   t toggle side-by-side/inline · i list/tree · gc fold unchanged

local data = vim.fn.stdpath("data")
vim.opt.rtp:prepend(data .. "/lazy/codediff.nvim")
vim.opt.rtp:prepend(data .. "/lazy/gruvbox.nvim")

vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.o.number = true
vim.o.signcolumn = "yes"
vim.o.termguicolors = true
vim.o.background = "dark"
-- The popup loads real working-tree files for the diff; if one is already open
-- elsewhere (your main nvim) or has a stale swap, bufload would raise E325
-- ATTENTION and halt the popup. It's an ephemeral read-only view, so don't make
-- swaps and never prompt about existing ones.
vim.o.swapfile = false
vim.opt.shortmess:append("A")

local repo = vim.env.REPO
if repo and repo ~= "" then
  vim.cmd("cd " .. vim.fn.fnameescape(repo))
end

-- Warm dark theme so codediff's diff highlights read clearly: it draws
-- line-level diffs from DiffAdd/DiffDelete and derives char-level from them, so
-- the muddy default colorscheme made changes hard to see. gruvbox (dark) has a
-- warm dark background with well-defined, high-contrast diff groups (DiffText is
-- a bright amber, so changed chars pop). pcall-guarded so a missing plugin
-- degrades to the default colorscheme rather than erroring the popup.
pcall(function()
  vim.cmd.colorscheme("gruvbox")
end)

-- codediff config: side-by-side, explorer on the left. codediff does not bind
-- bare <space>, so our leader works. It DOES bind <leader>hs/hu/hr to
-- stage/unstage/discard hunk in diff buffers; this review-and-paste flow never
-- stages, so disable that trio (false = the keymap is not set).
require("codediff").setup({
  diff = { layout = "side-by-side" },
  explorer = { position = "left" },
  keymaps = {
    view = {
      stage_hunk = false,
      unstage_hunk = false,
      discard_hunk = false,
    },
  },
})

-- ── collection state ──────────────────────────────────────────────────────
local M = { collected = {} }

-- The HEAD/left side is a `codediff://` virtual buffer (filereadable returns 0);
-- the working-tree side is the real file on disk. Only the latter has line
-- numbers that match the actual file, so collection is restricted to it. The
-- filereadable check is the real guard; the scheme check is a fast early-out.
local function is_worktree_side()
  local name = vim.api.nvim_buf_get_name(0)
  if name == "" or name:match("^codediff://") then
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
-- :CodeDiff shows: working tree vs HEAD, incl. staged changes).
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

-- Jump to a collected ref's file+line within the open codediff view (best-effort).
-- Uses codediff's internal explorer API (mirrors its own focus_file recipe):
-- resolve the path to a status node, select it via on_file_select, then place the
-- cursor on the saved line in the modified pane once the async open settles.
-- Degrades to a no-op if the explorer or file cannot be found, rather than erroring.
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
  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  if not ok then
    return
  end
  -- The collected-list float is editor-relative, so it belongs to whatever tab
  -- was active when it opened — the codediff tab in this single-tab popup. If
  -- that invariant ever breaks, get_explorer returns nil below and we no-op.
  local tabpage = vim.api.nvim_get_current_tabpage()
  local explorer = lifecycle.get_explorer(tabpage)
  if not explorer or not explorer.status_result then
    return
  end
  -- Resolve path -> file node + group, in the plugin's own search order.
  local sr = explorer.status_result
  local file, group
  for _, g in ipairs({ "conflicts", "unstaged", "staged" }) do
    for _, f in ipairs(sr[g] or {}) do
      if f.path == path then
        file, group = f, g
        break
      end
    end
    if file then
      break
    end
  end
  if not file then
    return
  end
  -- Move the explorer cursor onto that node (mirrors codediff's get_node loop).
  if explorer.tree and explorer.winid and vim.api.nvim_win_is_valid(explorer.winid)
      and explorer.bufnr and vim.api.nvim_buf_is_valid(explorer.bufnr) then
    for l = 1, vim.api.nvim_buf_line_count(explorer.bufnr) do
      local node = explorer.tree:get_node(l)
      if node and node.data and node.data.path == file.path and node.data.group == group then
        vim.api.nvim_win_set_cursor(explorer.winid, { l, 0 })
        break
      end
    end
  end
  -- Open the diff with the exact file_data shape the plugin uses.
  explorer.on_file_select({
    path = file.path,
    old_path = file.old_path,
    status = file.status,
    git_root = explorer.git_root,
    group = group,
  })
  -- on_file_select opens the diff asynchronously (async git + scheduled render)
  -- and codediff itself jumps the cursor to the first change during that render.
  -- So we can't use a fixed delay: we poll until the modified pane actually holds
  -- THIS file's diff, then set our saved line LAST so it wins over the first-change
  -- jump. Bounded retries keep it best-effort — if the file never loads, no-op.
  local attempts = 0
  local function place_cursor()
    attempts = attempts + 1
    local _, modified_win = lifecycle.get_windows(tabpage)
    local _, modified_buf = lifecycle.get_buffers(tabpage)
    local ready = modified_win and vim.api.nvim_win_is_valid(modified_win)
      and modified_buf and vim.api.nvim_buf_is_valid(modified_buf)
      and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(modified_buf), ":.") == path
    if ready then
      local last = vim.api.nvim_buf_line_count(modified_buf)
      vim.api.nvim_win_set_cursor(modified_win, { math.min(s, last), 0 })
      vim.api.nvim_set_current_win(modified_win)
    elseif attempts < 20 then
      vim.defer_fn(place_cursor, 25)
    end
  end
  vim.defer_fn(place_cursor, 25)
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
  local pane = vim.env.ORIGIN_PANE
  if not pane or pane == "" then
    vim.notify("no origin pane — cannot paste", vim.log.levels.ERROR)
    return
  end
  -- The popup opens in any git repo; the paste target only needs to be Claude
  -- at confirm time. If the origin pane isn't running Claude, report and stay
  -- open (nothing is lost — the user can bail with q or retry).
  local tty = vim.trim(vim.fn.system(
    { "tmux", "display-message", "-p", "-t", pane, "#{pane_tty}" }))
  vim.fn.system({ vim.env.HOME .. "/.tmux/scripts/is-claude-pane.sh", tty })
  if vim.v.shell_error ~= 0 then
    vim.notify("origin pane is not running Claude — nothing sent", vim.log.levels.ERROR)
    return
  end
  local refs = table.concat(M.collected, " ") -- single line: no submit risk
  vim.fn.system({ "tmux", "send-keys", "-t", pane, "-l", refs })
  vim.cmd("qa!")
end

-- Re-point the popup at another git repo, cd-ing there and reopening codediff.
-- Collected refs are repo-relative, so switching clears them for a fresh context.
local function switch_repo(dir)
  if not dir or dir == "" or vim.fn.isdirectory(dir) == 0 then
    return
  end
  vim.fn.system({ "git", "-C", dir, "rev-parse", "--is-inside-work-tree" })
  if vim.v.shell_error ~= 0 then
    vim.notify("not a git repo: " .. dir, vim.log.levels.WARN)
    return
  end
  -- Tear down any open codediff view, then reset to a single empty buffer/tab so
  -- the next :CodeDiff takes the open path (not its toggle-close path).
  -- cleanup_all() clears codediff's session state (safe no-op when nothing is
  -- open); tabonly/enew/only then guarantee a clean single-window tab regardless
  -- of how much of its layout cleanup_all tore down.
  pcall(function() require("codediff.ui.lifecycle").cleanup_all() end)
  vim.cmd("silent! tabonly")
  vim.cmd("silent! enew")
  vim.cmd("silent! only")
  vim.cmd("cd " .. vim.fn.fnameescape(dir))
  if #M.collected > 0 then
    M.collected = {}
    vim.notify("switched repo — cleared collected refs")
  end
  -- Redraw the collected-list float (if open) so it shrinks to the cleared state.
  M.refresh_list()
  if M.list_win and vim.api.nvim_win_is_valid(M.list_win) then
    vim.api.nvim_win_set_height(M.list_win, 1)
  end
  vim.cmd("CodeDiff")
end

-- Show a cheatsheet of this popup's custom keys in a floating window.
function M.show_help()
  if M.help_win and vim.api.nvim_win_is_valid(M.help_win) then
    vim.api.nvim_win_close(M.help_win, true)
    M.help_win = nil
    return
  end
  local lines = {
    " diff-review popup ",
    "",
    " <leader>a     collect hunk (normal) / selection (visual)",
    "               — working-tree (right) side only",
    " <leader>l     toggle collected list (dd remove · CR jump · q close)",
    " <leader>z     jump to another git repo (zoxide)",
    " <leader><CR>  confirm: paste refs to origin pane",
    " q / :q        bail — quit, send nothing",
    " <leader>?     toggle this help",
    "",
    " nav: ]f/[f or Tab/S-Tab file · ]c/[c hunk · <C-h/j/k/l> windows",
    "      <CR> open file · t layout · i list/tree · gc fold unchanged",
  }
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local width = 64
  M.help_win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    anchor = "NW",
    row = math.max(0, math.floor((vim.o.lines - #lines) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = #lines,
    style = "minimal",
    border = "rounded",
    title = " keys ",
  })
  vim.keymap.set("n", "q", function() M.show_help() end, { buffer = buf })
  vim.keymap.set("n", "<leader>?", function() M.show_help() end, { buffer = buf })
end

-- Jump to another repo via a zoxide frecency picker (snacks if available, else
-- a plain vim.ui.select). snacks is loaded lazily here so popup startup stays fast.
function M.jump_repo()
  local ok = pcall(function()
    if not M._snacks_ready then
      vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/snacks.nvim")
      require("snacks").setup({})
      M._snacks_ready = true
    end
    require("snacks").picker.zoxide({
      confirm = function(picker, item)
        picker:close()
        if item then
          switch_repo(item.file)
        end
      end,
    })
  end)
  if ok then
    return
  end
  local dirs = vim.fn.systemlist({ "zoxide", "query", "--list" })
  if vim.v.shell_error ~= 0 or #dirs == 0 then
    vim.notify("zoxide returned nothing", vim.log.levels.WARN)
    return
  end
  vim.ui.select(dirs, { prompt = "Jump to repo:" }, function(choice)
    if choice then
      switch_repo(choice)
    end
  end)
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
vim.keymap.set("n", "<leader>z", M.jump_repo, { desc = "jump to another repo (zoxide)" })
vim.keymap.set("n", "<leader>?", M.show_help, { desc = "show diff-review key cheatsheet" })
vim.keymap.set("n", "<leader><CR>", M.confirm, { desc = "confirm & paste refs to Claude" })
vim.keymap.set("n", "q", function() vim.cmd("qa!") end, { desc = "bail (send nothing)" })

-- Tab / Shift-Tab cycle files too, as aliases for ]f/[f (old diffview muscle
-- memory). codediff's public navigation API acts on the current diff session, so
-- these work from both the explorer and the diff panes, and no-op when none is open.
vim.keymap.set("n", "<Tab>", function() require("codediff").next_file() end, { desc = "next file" })
vim.keymap.set("n", "<S-Tab>", function() require("codediff").prev_file() end, { desc = "prev file" })

-- Ctrl+h/j/k/l move between windows (file panel <-> diff sides), matching the
-- vim-tmux-navigator muscle memory. Plain wincmd — no tmux integration needed
-- inside the popup.
for _, k in ipairs({ "h", "j", "k", "l" }) do
  vim.keymap.set("n", "<C-" .. k .. ">", "<C-w>" .. k, { desc = "focus window " .. k })
end

-- Run after codediff opens or switches a file (scheduled so it runs AFTER
-- codediff sets its own keymaps/layout). Two jobs:
--  1. Re-assert `q -> qa!` on every window: codediff binds buffer-local `q` to
--     close its own view, which would otherwise shadow our global bail. (Our
--     floats set their own buffer-local q.)
--  2. Land focus in the working-tree (right) pane — the only side collection
--     works on — so `<leader>a` collects immediately without window-hopping.
--     It's identified the same way is_worktree_side() does: a real, readable
--     on-disk file (not the codediff:// HEAD side, not the nofile explorer).
local function on_codediff_ready()
  local worktree_win, rightmost_win, rightmost_col = nil, nil, -1
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    vim.keymap.set("n", "q", function() vim.cmd("qa!") end,
      { buffer = buf, desc = "bail (send nothing)" })
    local name = vim.api.nvim_buf_get_name(buf)
    -- Prefer the loaded working-tree file (accurate once content is in).
    if name ~= "" and not name:match("^codediff://") and vim.fn.filereadable(name) == 1 then
      worktree_win = win
    end
    -- Fallback: the rightmost non-explorer window. CodeDiffOpen fires before the
    -- async file content loads, when the modified pane is still a placeholder and
    -- isn't readable yet; focusing it by POSITION now (layout is
    -- explorer|HEAD|working-tree) means the content loads into the already-focused
    -- window, so there's no late, jarring focus jump.
    if vim.bo[buf].filetype ~= "codediff-explorer" then
      local col = vim.api.nvim_win_get_position(win)[2]
      if col > rightmost_col then
        rightmost_col, rightmost_win = col, win
      end
    end
  end
  local target = worktree_win or rightmost_win
  if target and vim.api.nvim_win_is_valid(target) then
    vim.api.nvim_set_current_win(target)
  end
end
vim.api.nvim_create_autocmd("User", {
  pattern = { "CodeDiffOpen", "CodeDiffFileSelect" },
  callback = function() vim.schedule(on_codediff_ready) end,
})

-- Does the current dir have anything to review? (inside a git work tree AND a
-- non-empty `git status`). cwd was set to REPO at startup.
local function cwd_has_changes()
  vim.fn.system({ "git", "rev-parse", "--is-inside-work-tree" })
  if vim.v.shell_error ~= 0 then
    return false
  end
  return #vim.fn.systemlist({ "git", "status", "--porcelain" }) > 0
end

-- Open once the UI is ready. With changes, show the working-tree diff; with none
-- (clean repo, or not a repo) drop straight into the zoxide repo picker so
-- prefix+e is never a confusing empty popup. Guarded so a headless syntax-check
-- (`nvim -u <this> +qa`) opens nothing.
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    if #vim.api.nvim_list_uis() == 0 then
      return
    end
    if cwd_has_changes() then
      vim.cmd("CodeDiff")
    else
      M.jump_repo()
    end
  end,
})
