# Claude Diff-Review Popup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A tmux popup (`prefix + e`), active only inside a Claude Code pane, that opens an isolated nvim showing Claude's working-tree diff via diffview; you collect hunk/visual-selection references, review them in a floating list, and on confirm the refs paste back into the originating Claude prompt as a single line.

**Architecture:** A tmux `if-shell` binding runs a tiny tty-based detection script; on success it opens `display-popup -E` running `nvim -u <standalone-init>`. The standalone init prepends the installed diffview/plenary to runtimepath (bypassing the user's normal config entirely), opens diffview against the working tree, and registers four keymaps backed by an in-memory ref list. Confirm sends the refs to the origin pane via `tmux send-keys -l` (single line, no Enter).

**Tech Stack:** tmux (`if-shell`, `display-popup`, `send-keys`), bash, Lua/Neovim, diffview.nvim (already installed), git.

---

## File Structure

- `dot_tmux/scripts/executable_is-claude-pane.sh` → `~/.tmux/scripts/is-claude-pane.sh` — detection test, exit 0/1.
- `dot_tmux/scripts/claude-diff-review-init.lua` → `~/.tmux/scripts/claude-diff-review-init.lua` — standalone nvim config (diffview + collection logic). Not executable, co-located with the script.
- `dot_tmux/conf.d/keys.conf` — add the `prefix + e` binding (modify).

All paths above are chezmoi *source* paths; deployed targets shown after `→`. Edits happen in the chezmoi source dir (`~/.local/share/chezmoi`), then `chezmoi apply` deploys them (Task 6).

---

### Task 1: tty-based Claude detection script

**Files:**
- Create: `dot_tmux/scripts/executable_is-claude-pane.sh`

- [ ] **Step 1: Write the detection script**

Create `dot_tmux/scripts/executable_is-claude-pane.sh`:

```bash
#!/usr/bin/env bash
# Exit 0 if a `claude` process is running on the given tty, else exit 1.
# Used by the prefix+e diff-review binding to gate the popup to Claude panes.
# Arg 1: a tty, with or without the /dev/ prefix (tmux #{pane_tty} form).
tty="${1#/dev/}"
[ -z "$tty" ] && exit 1
ps -t "$tty" -o command= 2>/dev/null | grep -q '[c]laude'
```

(The `[c]laude` bracket trick prevents the grep from matching its own process line.)

- [ ] **Step 2: Make it executable and verify it passes on THIS pane**

Run:
```bash
chmod +x ~/.local/share/chezmoi/dot_tmux/scripts/executable_is-claude-pane.sh
bash ~/.local/share/chezmoi/dot_tmux/scripts/executable_is-claude-pane.sh "$(tmux display-message -p '#{pane_tty}')"; echo "exit=$?"
```
Expected: `exit=0` (this pane runs Claude).

- [ ] **Step 3: Verify it fails for a non-Claude tty**

Run:
```bash
bash ~/.local/share/chezmoi/dot_tmux/scripts/executable_is-claude-pane.sh /dev/ttysDOESNOTEXIST; echo "exit=$?"
```
Expected: `exit=1` (no claude on that tty).

- [ ] **Step 4: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_tmux/scripts/executable_is-claude-pane.sh
git commit -m "feat(tmux): add tty-based claude-pane detection script"
```

---

### Task 2: Standalone nvim init that opens diffview

**Files:**
- Create: `dot_tmux/scripts/claude-diff-review-init.lua`

- [ ] **Step 1: Write the init skeleton (rtp + diffview open)**

Create `dot_tmux/scripts/claude-diff-review-init.lua`:

```lua
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
```

- [ ] **Step 2: Syntax-check by loading headless**

Run:
```bash
nvim --headless -u ~/.local/share/chezmoi/dot_tmux/scripts/claude-diff-review-init.lua +qa 2>&1; echo "exit=$?"
```
Expected: no Lua error output, `exit=0`. (The VimEnter guard skips DiffviewOpen in headless.)

- [ ] **Step 3: Verify diffview opens interactively**

Run (opens a real nvim in this repo, which has working-tree changes):
```bash
REPO="$HOME/.local/share/chezmoi" nvim -u ~/.local/share/chezmoi/dot_tmux/scripts/claude-diff-review-init.lua
```
Expected: diffview opens with the file panel on the left and the diff on the right. Quit with `:qa!`.

- [ ] **Step 4: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_tmux/scripts/claude-diff-review-init.lua
git commit -m "feat(nvim): standalone diff-review init opening diffview"
```

---

### Task 3: Hunk + visual collection into an in-memory ref list

**Files:**
- Modify: `dot_tmux/scripts/claude-diff-review-init.lua`

- [ ] **Step 1: Add state, side-detection, and the git-hunk parser**

Insert the following AFTER the `require("diffview").setup({})` line and BEFORE the `VimEnter` autocmd:

```lua
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
```

- [ ] **Step 2: Add the two collect functions**

Insert immediately after `add_ref`:

```lua
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
```

- [ ] **Step 3: Register the collect keymaps**

Insert after `M.collect_visual`:

```lua
vim.keymap.set("n", "<leader>a", M.collect_hunk, { desc = "collect hunk under cursor" })
vim.keymap.set("x", "<leader>a", M.collect_visual, { desc = "collect visual selection" })
```

- [ ] **Step 4: Syntax-check headless**

Run:
```bash
nvim --headless -u ~/.local/share/chezmoi/dot_tmux/scripts/claude-diff-review-init.lua +qa 2>&1; echo "exit=$?"
```
Expected: no Lua error, `exit=0`.

- [ ] **Step 5: Verify collection interactively**

Run:
```bash
REPO="$HOME/.local/share/chezmoi" nvim -u ~/.local/share/chezmoi/dot_tmux/scripts/claude-diff-review-init.lua
```
In diffview: move the cursor onto a changed line in the right-hand (current) file and press `<Space>a` → expect a `+ collected (1): path:start-stop` message. Visually select a few lines (`V`/`j`) on the right side and press `<Space>a` → expect `+ collected (2)`. Move to the LEFT (HEAD) side, press `<Space>a` → expect `select in the current-file side`. Quit with `:qa!`.

- [ ] **Step 6: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_tmux/scripts/claude-diff-review-init.lua
git commit -m "feat(nvim): collect hunk and visual-selection refs in diff-review"
```

---

### Task 4: Floating collected-list (toggle, prune, jump)

**Files:**
- Modify: `dot_tmux/scripts/claude-diff-review-init.lua`

- [ ] **Step 1: Add list rendering + toggle**

Insert AFTER `add_ref` and BEFORE `M.collect_hunk`:

```lua
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
```

- [ ] **Step 2: Register the list toggle keymap**

Add alongside the other top-level keymaps (after the collect keymaps from Task 3):

```lua
vim.keymap.set("n", "<leader>l", M.toggle_list, { desc = "toggle collected list" })
```

- [ ] **Step 3: Syntax-check headless**

Run:
```bash
nvim --headless -u ~/.local/share/chezmoi/dot_tmux/scripts/claude-diff-review-init.lua +qa 2>&1; echo "exit=$?"
```
Expected: no Lua error, `exit=0`.

- [ ] **Step 4: Verify the list interactively**

Run:
```bash
REPO="$HOME/.local/share/chezmoi" nvim -u ~/.local/share/chezmoi/dot_tmux/scripts/claude-diff-review-init.lua
```
Collect 2-3 refs (`<Space>a`), press `<Space>l` → a bordered float lists them top-right. Press `dd` on one → it disappears and the float shrinks. Press `<CR>` on a remaining one → diffview switches to that file with the cursor near the line. Press `q` → float closes. Quit `:qa!`.

- [ ] **Step 5: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_tmux/scripts/claude-diff-review-init.lua
git commit -m "feat(nvim): floating collected-list with prune and jump"
```

---

### Task 5: Confirm (paste refs) and bail

**Files:**
- Modify: `dot_tmux/scripts/claude-diff-review-init.lua`

- [ ] **Step 1: Add the confirm function**

Insert after `M.toggle_list` (and before the keymap registrations):

```lua
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
```

- [ ] **Step 2: Register confirm + global bail keymaps**

Add alongside the other top-level keymaps:

```lua
vim.keymap.set("n", "<leader><CR>", M.confirm, { desc = "confirm & paste refs to Claude" })
vim.keymap.set("n", "q", function() vim.cmd("qa!") end, { desc = "bail (send nothing)" })
```

- [ ] **Step 3: Ensure `q` bails even in the diffview file panel**

The diffview file-panel buffer sets its own buffer-local maps; re-assert `q` there. Add this autocmd just before the `VimEnter` autocmd:

```lua
vim.api.nvim_create_autocmd("BufWinEnter", {
  callback = function(ev)
    local ft = vim.bo[ev.buf].filetype or ""
    if ft:match("^Diffview") then
      vim.keymap.set("n", "q", function() vim.cmd("qa!") end,
        { buffer = ev.buf, desc = "bail (send nothing)" })
    end
  end,
})
```

(The floating list's buffer-local `q` from Task 4 still wins inside the list, closing only the float.)

- [ ] **Step 4: Syntax-check headless**

Run:
```bash
nvim --headless -u ~/.local/share/chezmoi/dot_tmux/scripts/claude-diff-review-init.lua +qa 2>&1; echo "exit=$?"
```
Expected: no Lua error, `exit=0`.

- [ ] **Step 5: Verify confirm sends a single line to a target pane**

Set up a throwaway target pane that captures what it receives, then drive nvim against it:
```bash
tmux new-session -d -s reviewtest -x 100 -y 30 'cat > /tmp/review_confirm.txt'
sleep 0.4
TARGET=$(tmux list-panes -t reviewtest -F '#{pane_id}' | head -1)
CLAUDE_PANE="$TARGET" REPO="$HOME/.local/share/chezmoi" \
  nvim -u ~/.local/share/chezmoi/dot_tmux/scripts/claude-diff-review-init.lua
# In nvim: collect 2 refs with <Space>a, then press <Space><CR> (confirms + quits).
tmux send-keys -t "$TARGET" C-d   # close the cat
sleep 0.3
tmux kill-session -t reviewtest 2>/dev/null
echo "=== captured ==="; cat /tmp/review_confirm.txt; echo
```
Expected: `/tmp/review_confirm.txt` contains the collected refs on ONE line, space-separated, with NO trailing newline.

- [ ] **Step 6: Verify bail sends nothing**

```bash
rm -f /tmp/review_bail.txt
tmux new-session -d -s bailtest -x 100 -y 30 'cat > /tmp/review_bail.txt'
sleep 0.4
TARGET=$(tmux list-panes -t bailtest -F '#{pane_id}' | head -1)
CLAUDE_PANE="$TARGET" REPO="$HOME/.local/share/chezmoi" \
  nvim -u ~/.local/share/chezmoi/dot_tmux/scripts/claude-diff-review-init.lua
# In nvim: collect a ref, then press q to bail.
tmux send-keys -t "$TARGET" C-d
sleep 0.3
tmux kill-session -t bailtest 2>/dev/null
echo "=== captured (should be empty) ==="; cat /tmp/review_bail.txt; echo "<<end>>"
```
Expected: file is empty (`<<end>>` immediately after the marker).

- [ ] **Step 7: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_tmux/scripts/claude-diff-review-init.lua
git commit -m "feat(nvim): confirm pastes single-line refs to Claude pane; q bails"
```

---

### Task 6: Wire the tmux binding and end-to-end test

**Files:**
- Modify: `dot_tmux/conf.d/keys.conf`

- [ ] **Step 1: Add the `prefix + e` binding**

Append to `dot_tmux/conf.d/keys.conf` (after the existing `bind-key "t" ... lazygit` block):

```tmux
# prefix+e — review Claude's working-tree diff in a popup, collect hunk refs.
# Only opens when the active pane is running Claude (tty-based detection).
bind e if-shell "~/.tmux/scripts/is-claude-pane.sh #{pane_tty}" \
  "display-popup -E -w 90% -h 90% -d '#{pane_current_path}' \
     -e CLAUDE_PANE=#{pane_id} -e REPO=#{pane_current_path} \
     'nvim -u ~/.tmux/scripts/claude-diff-review-init.lua'"
```

- [ ] **Step 2: Deploy with chezmoi**

Per the user's deploy flow, review then apply (do NOT use `--force`):
```bash
cd ~/.local/share/chezmoi
chezmoi diff
chezmoi apply
```
Expected: `~/.tmux/scripts/is-claude-pane.sh`, `~/.tmux/scripts/claude-diff-review-init.lua`, and the updated `~/.tmux/conf.d/keys.conf` are written.

- [ ] **Step 3: Reload tmux config**

Run:
```bash
tmux source-file ~/.tmux.conf
```
Expected: no errors printed.

- [ ] **Step 4: End-to-end test from THIS Claude pane**

In this pane press `<prefix> e` (prefix is `C-Space`). Expected: the popup opens with diffview showing the chezmoi repo's working-tree changes. Collect a hunk (`<Space>a`), open the list (`<Space>l`), confirm (`<Space><CR>`). Expected: the popup closes and the ref (e.g. `dot_tmux/conf.d/keys.conf:NN-MM`) appears at this Claude prompt with the cursor after it and nothing auto-submitted.

- [ ] **Step 5: Negative test from a non-Claude pane**

Open a plain shell pane (`<prefix> c` or split), and from it press `<prefix> e`. Expected: nothing happens (no popup).

- [ ] **Step 6: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_tmux/conf.d/keys.conf
git commit -m "feat(tmux): bind prefix+e to Claude diff-review popup"
```

---

## Notes / known follow-ups (from spec validation)

- **Multi-line ref mode** (one ref per line) is intentionally NOT built — it needs bracketed paste (`load-buffer` + `paste-buffer -p`) whose marker emission must be confirmed against a live Claude prompt. Single-line is the validated default. Revisit only if requested.
- **diffview internal API** (`lib.get_current_view()`, `view.panel:ordered_file_list()`, `view:set_file`) is used only for the list `<CR>` jump (Task 4). If a diffview update breaks it, the `pcall` guards degrade gracefully (jump no-ops); collection/confirm do not depend on it.
