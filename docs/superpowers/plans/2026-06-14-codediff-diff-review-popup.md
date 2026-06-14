# Codediff Diff-Review Popup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Swap the `prefix+e` Claude diff-review popup's diff engine from diffview.nvim to codediff.nvim, dropping all custom popup theming, while keeping the collect-hunks-and-paste-to-Claude workflow identical.

**Architecture:** The popup is a standalone `nvim -u <init>` that loads none of the user's normal config. We register codediff via lazy (diffview stays for neogit), rewrite the diffview-specific lines of the init (rtp, setup, open, close, q-bail, jump), delete the now-orphaned `popup_ui.lua`, and lean on the default colorscheme plus codediff's auto-adapt for the look. The collection engine (`is_worktree_side`, `hunk_range_at`, `add_ref`, the collected float, `confirm`) is plugin-agnostic and untouched.

**Tech Stack:** Neovim/Lua, lazy.nvim, codediff.nvim (esmuellert), tmux popup, git, chezmoi.

**Spec:** `docs/superpowers/specs/2026-06-14-codediff-diff-review-popup-design.md`

---

## Conventions for every task

- All source files are **chezmoi-managed**. Edit the chezmoi source under
  `~/.local/share/chezmoi/...`, then run `chezmoi apply` so the change lands at
  `~/...` where the popup actually reads it.
- Git operations run in the chezmoi repo: `cd ~/.local/share/chezmoi`.
- The automated gate is the headless syntax check:
  `nvim --headless -u ~/.tmux/scripts/claude-diff-review-init.lua +qa`
  It must exit 0 and print no Lua errors. The init's `VimEnter` guard
  (`#vim.api.nvim_list_uis() > 0`) skips opening the diff in headless, so this
  only validates that the file parses and its top-level code runs.
- Interactive checks are run by the user with `prefix+e` in tmux (after a file in
  some repo has working-tree changes to view).

---

## Task 1: Install codediff and validate the assumptions later tasks depend on

This is a setup + introspection task. It installs codediff and confirms the small
set of facts the concrete code in Tasks 3 to 5 relies on. Record each finding in
the task's commit message so later tasks (and reviewers) can see them.

**Files:**
- Create: `~/.local/share/chezmoi/dot_config/nvim/lua/zaid/plugins/codediff.lua`

- [ ] **Step 1: Create the lazy plugin spec**

Create `~/.local/share/chezmoi/dot_config/nvim/lua/zaid/plugins/codediff.lua`:

```lua
-- VSCode-style, C-backed diff viewer. Used by the standalone diff-review popup
-- (~/.tmux/scripts/claude-diff-review-init.lua); diffview stays as neogit's
-- engine. Lazy-loaded on the :CodeDiff command; the prebuilt binary
-- auto-downloads on first use.
return {
  "esmuellert/codediff.nvim",
  cmd = "CodeDiff",
}
```

- [ ] **Step 2: Apply and install the plugin**

```bash
chezmoi apply
nvim --headless "+Lazy! sync" +qa
```
Expected: lazy installs codediff into `~/.local/share/nvim/lazy/codediff.nvim`.
Verify the directory exists:
```bash
ls ~/.local/share/nvim/lazy/codediff.nvim
```
Expected: the plugin's files are present (`lua/`, `README.md`, etc.).

- [ ] **Step 3: Warm the binary and confirm codediff opens**

In a repo that has uncommitted changes, open nvim and run `:CodeDiff`. The first
run downloads the prebuilt C binary (needs curl/wget + network). Confirm:
- the changed-files explorer appears,
- `]f`/`[f` move between files,
- `<CR>` on a file opens its side-by-side diff,
- the working-tree (right) side is an editable real-file buffer.

Quit with `:qa!`.

- [ ] **Step 4: Record the introspection findings**

Inspect `~/.local/share/nvim/lazy/codediff.nvim/lua/codediff/` and the live
buffers to confirm these five facts. Note each in the commit message:

1. **Open in new tab?** After `:CodeDiff`, does it open in a new tabpage or the
   current one? (Run `:tabs` while it is open.) Confirms the `tabonly` reset in
   Task 4 is appropriate.
2. **Explorer buffer type.** With the cursor in the explorer panel, run
   `:echo &buftype` and `:echo &filetype`. Expected: `buftype=nofile`. Task 5's
   jump uses `buftype == "nofile"` to find the explorer window.
3. **Explorer lines contain file paths.** Run `:lua print(vim.inspect(vim.api.nvim_buf_get_lines(0,0,-1,false)))` in the explorer buffer; confirm each
   changed file's path (or at least its basename) appears verbatim in a line.
   Task 5 matches on this text.
4. **`<CR>` selects a file in the explorer.** Confirmed in Step 3; note it.
5. **Does `<space>` do anything?** In the explorer and in a diff window, press
   `<space>` and confirm it is NOT bound to a codediff action (so the popup can
   safely use it as leader without disabling anything). Also confirm the
   `User CodeDiffOpen` and `User CodeDiffFileSelect` autocmd events fire (set a
   throwaway `:au User CodeDiffOpen echom "open"` before running `:CodeDiff`).

If any finding contradicts the assumption noted, adjust the relevant later task's
code before implementing it and note the deviation.

- [ ] **Step 5: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_config/nvim/lua/zaid/plugins/codediff.lua
git commit -m "feat(nvim): install codediff.nvim for the diff-review popup

Findings (live introspection):
- opens in: <new tab|current tab>
- explorer buftype/ft: <values>
- explorer lines contain file paths: <yes/no, full path or basename>
- <CR> selects file in explorer: yes
- <space> unbound by codediff: <yes/no>
- User CodeDiffOpen/CodeDiffFileSelect fire: <yes/no>"
```

---

## Task 2: Rewrite the init's loading, theming, and open path

Replaces the diffview rtp/setup/open with codediff, removes the popup_ui call and
the `<space>`-disable block, and deletes the orphaned `popup_ui.lua`.

**Files:**
- Modify: `~/.local/share/chezmoi/dot_tmux/scripts/claude-diff-review-init.lua`
  (lines 19-52 region and the `VimEnter` block near the end)
- Delete: `~/.local/share/chezmoi/dot_config/nvim/lua/zaid/popup_ui.lua`

- [ ] **Step 1: Replace the rtp prepend + theming block**

In `claude-diff-review-init.lua`, replace the current lines 19-43 (the
`data`/rtp prepend of plenary + diffview, the option sets, the `cd` to REPO, and
the `package.path ... require("zaid.popup_ui").apply()` block) with:

```lua
local data = vim.fn.stdpath("data")
vim.opt.rtp:prepend(data .. "/lazy/codediff.nvim")

vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.o.number = true
vim.o.signcolumn = "yes"
vim.o.termguicolors = true
vim.o.background = "dark"

local repo = vim.env.REPO
if repo and repo ~= "" then
  vim.cmd("cd " .. vim.fn.fnameescape(repo))
end
```

This drops the plenary + diffview prepends and the entire `popup_ui` block. The
look now comes from the default colorscheme plus codediff's auto-adapt.

- [ ] **Step 2: Replace the diffview setup block with codediff setup**

Replace the current `require("diffview").setup({...})` block (the keymaps that
disable `<space>`, lines 45-52) with:

```lua
-- codediff config: side-by-side, explorer on the left. codediff does not bind
-- bare <space>, so our leader works. It DOES bind <leader>hs/hu/hr to
-- stage/unstage/discard hunk in diff buffers; this review-and-paste flow never
-- stages, so disable that trio (false = the keymap is not set; verified against
-- codediff's `if keymaps.<name> then vim.keymap.set(...)` guards).
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
```

- [ ] **Step 3: Replace the diffview open with the codediff command**

Replace the `VimEnter` callback body that calls `require("diffview").open()`:

```lua
-- Open the working-tree diff once the UI is ready. Guarded so a headless
-- `nvim -u <this> +qa` (used for syntax-checking) does not try to open it.
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    if #vim.api.nvim_list_uis() > 0 then
      vim.cmd("CodeDiff")
    end
  end,
})
```

- [ ] **Step 4: Delete the orphaned popup_ui module**

```bash
git -C ~/.local/share/chezmoi rm dot_config/nvim/lua/zaid/popup_ui.lua
```
(`git rm` in the chezmoi repo; `chezmoi apply` in the next step removes the
applied copy at `~/.config/nvim/lua/zaid/popup_ui.lua`.)

- [ ] **Step 5: Apply and syntax-check**

```bash
chezmoi apply
nvim --headless -u ~/.tmux/scripts/claude-diff-review-init.lua +qa; echo "exit=$?"
```
Expected: `exit=0`, no Lua error output. (`popup_ui` is no longer required, so its
removal does not error.)

- [ ] **Step 6: Interactive check**

`prefix+e` in a repo with working-tree changes. Expected: codediff opens the
changed-files explorer with the default-colorscheme look; `]f`/`[f` navigate;
`<CR>` opens a file's diff. `q` behavior is fixed in Task 3 (it may currently
close only the codediff view, not the popup). Bail with `:qa!` for now.

- [ ] **Step 7: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_tmux/scripts/claude-diff-review-init.lua dot_config/nvim/lua/zaid/popup_ui.lua
git commit -m "refactor(nvim): open codediff in the diff-review popup, drop popup_ui"
```

---

## Task 3: Make `q` bail the whole popup on codediff buffers

codediff binds buffer-local `q` to close its own view, shadowing the global
`q -> qa!`. Re-assert `q -> qa!` on the popup's windows whenever codediff opens or
switches a file, using the documented `User CodeDiffOpen`/`CodeDiffFileSelect`
events (confirmed firing in Task 1).

**Files:**
- Modify: `~/.local/share/chezmoi/dot_tmux/scripts/claude-diff-review-init.lua`
  (the `BufWinEnter` autocmd near the end that matches `^Diffview` filetypes)

- [ ] **Step 1: Replace the Diffview filetype autocmd**

Replace the current `BufWinEnter` autocmd that rebinds `q` on `^Diffview`
filetypes with:

```lua
-- codediff binds buffer-local `q` to close its own view, which would shadow our
-- global `q -> qa!`. Re-assert the bail binding across the popup's windows after
-- codediff opens or selects a file (scheduled so it runs AFTER codediff sets its
-- own keymaps). Our floats (collected list, help) set their own buffer-local q.
local function rebind_bail()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    vim.keymap.set("n", "q", function() vim.cmd("qa!") end,
      { buffer = buf, desc = "bail (send nothing)" })
  end
end
vim.api.nvim_create_autocmd("User", {
  pattern = { "CodeDiffOpen", "CodeDiffFileSelect" },
  callback = function() vim.schedule(rebind_bail) end,
})
```

- [ ] **Step 2: Apply and syntax-check**

```bash
chezmoi apply
nvim --headless -u ~/.tmux/scripts/claude-diff-review-init.lua +qa; echo "exit=$?"
```
Expected: `exit=0`, no errors.

- [ ] **Step 3: Interactive check**

`prefix+e`. In the explorer, press `q`: the whole popup closes. Reopen, `<CR>`
into a file diff, press `q`: the whole popup closes. (Both should `qa!`, not just
close the codediff view.)

- [ ] **Step 4: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_tmux/scripts/claude-diff-review-init.lua
git commit -m "fix(nvim): q bails the diff-review popup on codediff buffers"
```

---

## Task 4: Fix repo-switching teardown for codediff

`switch_repo` currently calls `require("diffview").close()`. Replace it with an
engine-agnostic teardown (collapse extra tabpages/windows, fresh buffer) and
reopen with `:CodeDiff`. Everything else in `switch_repo`/`jump_repo` (ref
clearing, the zoxide picker) is unchanged.

**Files:**
- Modify: `~/.local/share/chezmoi/dot_tmux/scripts/claude-diff-review-init.lua`
  (the `switch_repo` function)

- [ ] **Step 1: Replace the diffview close call in switch_repo**

In `switch_repo`, replace the line `pcall(function() require("diffview").close() end)`
with an engine-agnostic teardown, and replace the final
`require("diffview").open()` with `vim.cmd("CodeDiff")`. The full function becomes:

```lua
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
  -- the next :CodeDiff takes the open path (not its toggle-close path). Sequence
  -- per codediff source: cleanup_all() clears session state/highlights/keymaps
  -- but does NOT close windows/tabs (and is a safe no-op when nothing is open);
  -- tabonly/enew/only do the actual window reset. Re-running :CodeDiff from the
  -- codediff tab would instead toggle-close (and `qall` if it's the last tab),
  -- which is why we reset to a clean non-diff state first.
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
```

- [ ] **Step 2: Apply and syntax-check**

```bash
chezmoi apply
nvim --headless -u ~/.tmux/scripts/claude-diff-review-init.lua +qa; echo "exit=$?"
```
Expected: `exit=0`, no errors.

- [ ] **Step 3: Interactive check**

`prefix+e`, collect a hunk (`<leader>a`), then `<leader>z` and pick another repo
from the zoxide list. Expected: the popup tears down and reopens codediff against
the new repo; a "switched repo — cleared collected refs" notice appears; the
collected list (if open) shows "(nothing collected)".

- [ ] **Step 4: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_tmux/scripts/claude-diff-review-init.lua
git commit -m "fix(nvim): repo-switch teardown uses codediff, not diffview"
```

---

## Task 5: Reimplement jump_to for codediff (best-effort)

The collected-list `<CR>` jump currently uses `diffview.lib`. Reimplement it
against codediff's internal explorer API (the same recipe codediff uses for its
own `focus_file`): get the explorer for the current tab, resolve the ref's path
to a file node (searching conflicts → unstaged → staged, matching the plugin's
`find_file_in_status` order), move the explorer cursor to that node, call
`explorer.on_file_select(file_data)` to open the diff, then — because the open is
async and only jumps to the first change — place the cursor on the saved line in
the modified pane after a short defer.

**Files:**
- Modify: `~/.local/share/chezmoi/dot_tmux/scripts/claude-diff-review-init.lua`
  (the `M.jump_to` function)

- [ ] **Step 1: Replace M.jump_to**

Replace the entire `M.jump_to` function with:

```lua
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
  if explorer.winid and vim.api.nvim_win_is_valid(explorer.winid)
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
  -- on_file_select opens asynchronously and only jumps to the first change, so
  -- place the cursor on the saved line in the modified pane after it settles.
  vim.schedule(function()
    vim.defer_fn(function()
      local _, modified_win = lifecycle.get_windows(tabpage)
      if modified_win and vim.api.nvim_win_is_valid(modified_win) then
        local _, modified_buf = lifecycle.get_buffers(tabpage)
        local last = (modified_buf and vim.api.nvim_buf_is_valid(modified_buf)
          and vim.api.nvim_buf_line_count(modified_buf)) or s
        vim.api.nvim_win_set_cursor(modified_win, { math.min(s, last), 0 })
        vim.api.nvim_set_current_win(modified_win)
      end
    end, 50)
  end)
end
```

- [ ] **Step 2: Apply and syntax-check**

```bash
chezmoi apply
nvim --headless -u ~/.tmux/scripts/claude-diff-review-init.lua +qa; echo "exit=$?"
```
Expected: `exit=0`, no errors.

- [ ] **Step 3: Interactive check**

`prefix+e` in a repo with changes across at least two files. Collect a hunk in
each (`<leader>a`), open the list (`<leader>l`), move to the second ref and press
`<CR>`. Expected: the list closes, codediff selects that ref's file, and the
cursor lands on (or near) the saved start line.

- [ ] **Step 4: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_tmux/scripts/claude-diff-review-init.lua
git commit -m "feat(nvim): reimplement collected-ref jump for codediff"
```

---

## Task 6: Update help text, header comment, and nav hints

Bring the user-facing text in line with codediff's keys. No behavior change.

**Files:**
- Modify: `~/.local/share/chezmoi/dot_tmux/scripts/claude-diff-review-init.lua`
  (the header docstring lines 1-17 and the `M.show_help` `lines` table)

- [ ] **Step 1: Update the header docstring nav line**

In the header comment block, replace the two diffview nav lines:

```
-- Diffview nav: <Tab>/<S-Tab> next/prev file · j/k panel · <CR>/o/l open
--   <C-h/j/k/l> move between windows · ]c/[c hunk · <C-f>/<C-b> scroll
--   <leader>e panel · <leader>b toggle panel · g? diffview help
```

with:

```
-- codediff nav: ]f/[f next/prev file · <CR> open file from explorer
--   <C-h/j/k/l> move between windows · ]c/[c hunk · <C-f>/<C-b> scroll
--   t toggle side-by-side/inline · i list/tree · gc fold unchanged
```

Also update the top docstring's first descriptive line if it names diffview:
change "Reuses the diffview/plenary already installed by lazy.nvim" to
"Reuses codediff.nvim (installed by lazy.nvim)".

- [ ] **Step 2: Update the show_help nav lines**

In `M.show_help`, replace the last two entries of the `lines` table:

```lua
    " nav: Tab/S-Tab file · ]c/[c hunk · <C-h/j/k/l> windows",
    "      <leader>e panel · <leader>b toggle panel · g? diffview help",
```

with:

```lua
    " nav: ]f/[f file · ]c/[c hunk · <C-h/j/k/l> windows",
    "      <CR> open file · t layout · i list/tree · gc fold unchanged",
```

- [ ] **Step 3: Apply and syntax-check**

```bash
chezmoi apply
nvim --headless -u ~/.tmux/scripts/claude-diff-review-init.lua +qa; echo "exit=$?"
```
Expected: `exit=0`, no errors.

- [ ] **Step 4: Interactive check**

`prefix+e`, press `<leader>?`. Expected: the cheatsheet shows the codediff nav
keys (`]f/[f`, `<CR>`, `t`, `i`, `gc`) and no diffview-only keys.

- [ ] **Step 5: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_tmux/scripts/claude-diff-review-init.lua
git commit -m "docs(nvim): update diff-review popup help text for codediff"
```

---

## Task 7: End-to-end verification of the send-to-Claude flow

No new code. Confirms the whole popup works against codediff, with emphasis on
the paste-to-Claude path (the core feature), then syncs via chezmoi.

- [ ] **Step 1: Full manual run**

From a Claude pane in tmux, in a repo with working-tree changes across two files:
1. `prefix+e` -> codediff explorer opens (default look, no errors).
2. `]f`/`[f` navigate files; `<CR>` opens a diff.
3. On the working-tree (right) side, `<leader>a` on a changed line ->
   "+ collected (1): path:start-stop".
4. Visually select a few lines on the right side, `<leader>a` -> "+ collected (2)".
5. On the read-only (left) side, `<leader>a` -> "select in the current-file side"
   (collects nothing).
6. `<leader>l` -> list shows both refs; `dd` removes one; `<CR>` jumps to a ref;
   `q` closes the list.
7. `<leader>z` -> pick another repo -> view switches, refs cleared.
8. Back in the original repo (reopen if needed), collect a ref, then
   `<leader><CR>` -> the refs are pasted (not submitted) into the Claude pane's
   prompt as a single space-joined line.
9. `q` from any codediff buffer bails the popup.

Expected: every step behaves as described; the paste in step 8 matches the old
diffview behavior exactly.

- [ ] **Step 2: Negative / headless gate**

```bash
nvim --headless -u ~/.tmux/scripts/claude-diff-review-init.lua +qa; echo "exit=$?"
```
Expected: `exit=0`, no Lua errors.

- [ ] **Step 3: Sync via chezmoi**

Use the chezmoi-sync skill to validate and push the chezmoi changes (the commits
from Tasks 1 to 6). If running manually:
```bash
cd ~/.local/share/chezmoi && git status && git push
```
Expected: working tree clean, all popup commits pushed.

---

## Self-review notes

- **Spec coverage:** install + diffview-stays (Task 1), remove popup_ui (Task 2),
  rtp/setup/open swap (Task 2), q-bail (Task 3), switch_repo close (Task 4),
  jump_to best-effort (Task 5), help/comments (Task 6), unchanged collection
  engine verified end-to-end incl. paste-to-Claude (Task 7). Binary pre-warm is
  handled by Task 1 Step 3 (run once during dev) rather than a build hook, since
  warming it once is sufficient for this single user; the spec allowed either.
- **No placeholders:** all code blocks are complete. The only runtime-discovered
  facts (Task 1) are validations of assumptions already baked into concrete code;
  if a finding contradicts an assumption, the affected task says to adjust before
  implementing.
- **Naming consistency:** `M.collected`, `M.list_win`, `M.refresh_list`,
  `M.jump_to`, `switch_repo`, `rebind_bail` match across tasks and the existing
  file.
