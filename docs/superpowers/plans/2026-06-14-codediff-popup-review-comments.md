# Diff-Review Popup: Review Comments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-selection review comments to the `prefix+e` diff-review popup — write a comment per hunk/visual-range, then `Space <CR>` compiles them into one message pasted into the Claude pane — plus a confirm-on-quit guard.

**Architecture:** All edits are in the single standalone init `dot_tmux/scripts/claude-diff-review-init.lua`. `M.collected` becomes a list of `{ref, comment}` records; `Space a` opens a floating scratch comment buffer instead of auto-collecting; `confirm` compiles records and delivers multi-line via a tmux bracketed paste; `q` routes through a confirm-if-collected `M.bail`.

**Tech Stack:** Neovim/Lua, codediff.nvim, tmux (load-buffer/paste-buffer), git, chezmoi.

**Spec:** `docs/superpowers/specs/2026-06-14-codediff-popup-review-comments-design.md`

---

## Conventions for every task

- The file is **chezmoi-managed**. Edit the source at
  `~/.local/share/chezmoi/dot_tmux/scripts/claude-diff-review-init.lua`, then
  `chezmoi apply ~/.tmux/scripts/claude-diff-review-init.lua` so the live copy
  updates. (A full `chezmoi apply` may fail on an unrelated 1Password `.age`
  file; applying just this path avoids that.)
- Git ops run in the chezmoi repo: `cd ~/.local/share/chezmoi`. Work is on branch
  `feat/codediff-popup-review-comments`.
- There is no Lua unit-test harness. The automated gate per task is the headless
  syntax check:
  `nvim --headless -u ~/.tmux/scripts/claude-diff-review-init.lua +qa; echo "exit=$?"`
  It must print `exit=0` with no Lua error lines (the VimEnter guard skips opening
  in headless).
- Interactive checks are run by the user via `prefix+e`; each task lists them but
  they are not blocking for the automated gate.

---

## Task 1: Convert collected refs to {ref, comment} records + compile/paste

Change the data model and the consumers that read it, and rewrite `confirm` to
emit the compiled review-comment message via bracketed paste. Collection still
auto-adds (bare, empty comment) at this stage — the comment buffer comes in Task
2 — so the file stays working and testable.

**Files:**
- Modify: `~/.local/share/chezmoi/dot_tmux/scripts/claude-diff-review-init.lua`

- [ ] **Step 1: Make `add_ref` build a record**

Replace the `add_ref` function (currently pushes a string):

```lua
local function add_ref(s, e)
  local ref = rel_path() .. ":" .. s .. "-" .. e
  table.insert(M.collected, { ref = ref, comment = "" })
  vim.notify("+ collected (" .. #M.collected .. "): " .. ref)
end
```

- [ ] **Step 2: Render records in `list_lines`**

Replace `list_lines`:

```lua
local function list_lines()
  if #M.collected == 0 then
    return { "(nothing collected)" }
  end
  local out = {}
  for _, entry in ipairs(M.collected) do
    local first = "(no comment)"
    if entry.comment ~= "" then
      first = vim.split(entry.comment, "\n", { plain = true })[1]
    end
    local line = entry.ref .. "  │ " .. first
    if #line > 58 then
      line = line:sub(1, 57) .. "…"
    end
    table.insert(out, line)
  end
  return out
end
```

- [ ] **Step 3: Read `entry.ref` in the list-float `<CR>` handler**

In `M.toggle_list`, the `<CR>` keymap currently calls `M.jump_to(M.collected[idx])`.
Change it to pass the ref string:

```lua
  vim.keymap.set("n", "<CR>", function()
    local idx = vim.fn.line(".")
    if M.collected[idx] then
      M.jump_to(M.collected[idx].ref)
    end
  end, { buffer = buf, desc = "jump to ref" })
```

(`M.jump_to` itself is unchanged — it already takes a ref string. The `dd`
handler is unchanged — `table.remove(M.collected, idx)` works on records.)

- [ ] **Step 4: Rewrite `confirm` to compile records + bracketed paste**

Replace the body of `M.confirm` from the `local refs = ...` line through
`vim.cmd("qa!")` (keep the empty-check, origin-pane, and is-claude-pane guards
above it exactly as they are):

```lua
  -- Compile the collected records into one review-comment message.
  local lines = { "Please address these review comments:", "" }
  for _, entry in ipairs(M.collected) do
    table.insert(lines, "## " .. entry.ref)
    if entry.comment ~= "" then
      for _, cl in ipairs(vim.split(entry.comment, "\n", { plain = true })) do
        table.insert(lines, cl)
      end
    end
    table.insert(lines, "")
  end
  -- Deliver multi-line safely: a single `send-keys -l` would submit at each
  -- newline. Load the text into a tmux paste buffer and paste it with bracketed
  -- paste (-p) so the Claude TUI inserts it into the prompt WITHOUT submitting;
  -- -d drops the buffer after.
  local tmpfile = vim.fn.tempname()
  vim.fn.writefile(lines, tmpfile)
  vim.fn.system({ "tmux", "load-buffer", tmpfile })
  vim.fn.system({ "tmux", "paste-buffer", "-p", "-d", "-t", pane })
  vim.fn.delete(tmpfile)
  vim.cmd("qa!")
```

- [ ] **Step 5: Apply and syntax-check**

```bash
chezmoi apply ~/.tmux/scripts/claude-diff-review-init.lua
nvim --headless -u ~/.tmux/scripts/claude-diff-review-init.lua +qa; echo "exit=$?"
```
Expected: `exit=0`, no errors.

- [ ] **Step 6: Interactive check**

`prefix+e` in a repo with changes. `Space a` on a couple of hunks (still
auto-collects, no prompt yet). `Space l` shows `ref │ (no comment)` lines.
`Space <CR>` → the Claude pane receives the multi-line `Please address these
review comments:` block with `## ref` headers (and no comment bodies yet),
inserted into the prompt **without** submitting.

- [ ] **Step 7: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_tmux/scripts/claude-diff-review-init.lua
git commit -m "feat(nvim): diff-review collected refs become {ref,comment} records"
```

---

## Task 2: Comment scratch buffer on collect

Add `M.open_comment_buffer` and route `collect_hunk`/`collect_visual` through it,
so `Space a` opens a multi-line comment buffer. Remove the now-unused `add_ref`.

**Files:**
- Modify: `~/.local/share/chezmoi/dot_tmux/scripts/claude-diff-review-init.lua`

- [ ] **Step 1: Add `M.open_comment_buffer`**

Insert this function immediately ABOVE `function M.collect_hunk()`:

```lua
-- Floating scratch buffer to write (or edit) a comment for `ref`. Saves the
-- {ref, comment} record on <leader>qw (mirrors the user's :w); cancels on <C-c>
-- or q (buffer-local, so they don't trigger the global bail). With
-- `existing_index`, edits that entry in place instead of appending.
function M.open_comment_buffer(ref, existing_index)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  if existing_index and M.collected[existing_index] then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false,
      vim.split(M.collected[existing_index].comment, "\n", { plain = true }))
  end
  local width = math.min(80, vim.o.columns - 8)
  local height = math.min(12, math.max(4, vim.o.lines - 8))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    anchor = "NW",
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " ─ " .. ref .. " ─ ",
  })
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  local function save()
    local comment = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    comment = comment:gsub("^%s+", ""):gsub("%s+$", "")
    if existing_index and M.collected[existing_index] then
      M.collected[existing_index].comment = comment
      M.refresh_list()
      if M.list_win and vim.api.nvim_win_is_valid(M.list_win) then
        vim.api.nvim_win_set_height(M.list_win, math.max(1, #M.collected))
      end
    else
      table.insert(M.collected, { ref = ref, comment = comment })
      vim.notify("+ collected (" .. #M.collected .. "): " .. ref)
    end
    close()
  end
  vim.keymap.set("n", "<leader>qw", save, { buffer = buf, desc = "save comment" })
  vim.keymap.set({ "n", "i" }, "<C-c>", function()
    vim.cmd("stopinsert")
    close()
  end, { buffer = buf, desc = "cancel comment" })
  vim.keymap.set("n", "q", close, { buffer = buf, desc = "cancel comment" })
  vim.cmd("startinsert")
end
```

- [ ] **Step 2: Route `collect_hunk` through the comment buffer**

Replace the last line of `M.collect_hunk` (`add_ref(s, e)`) so the function ends:

```lua
  local s, e = hunk_range_at(vim.fn.line("."))
  if not s then
    vim.notify("no changed hunk under cursor", vim.log.levels.WARN)
    return
  end
  M.open_comment_buffer(rel_path() .. ":" .. s .. "-" .. e)
end
```

- [ ] **Step 3: Route `collect_visual` through the comment buffer**

Replace `M.collect_visual` (capture the ref before leaving the worktree buffer,
exit visual, then open the comment buffer on the next tick):

```lua
function M.collect_visual()
  if not is_worktree_side() then
    vim.notify("select in the current-file side", vim.log.levels.WARN)
    return
  end
  local s, e = vim.fn.line("v"), vim.fn.line(".")
  if s > e then
    s, e = e, s
  end
  local ref = rel_path() .. ":" .. s .. "-" .. e
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
  vim.schedule(function()
    M.open_comment_buffer(ref)
  end)
end
```

- [ ] **Step 4: Remove the now-unused `add_ref`**

Delete the entire `add_ref` function (the `local function add_ref(s, e) ... end`
block from Task 1). Nothing references it after Steps 2-3.

- [ ] **Step 5: Apply and syntax-check**

```bash
chezmoi apply ~/.tmux/scripts/claude-diff-review-init.lua
nvim --headless -u ~/.tmux/scripts/claude-diff-review-init.lua +qa; echo "exit=$?"
```
Expected: `exit=0`, no errors.

- [ ] **Step 6: Interactive check**

`prefix+e`. `Space a` on a hunk → comment buffer opens in insert mode; type two
lines; `Space q w` → `+ collected (1)`. Visual-select lines, `Space a`, `Ctrl-c`
→ cancelled, nothing added. `Space a`, save empty (`Space q w` with no text) →
collected with `(no comment)`.

- [ ] **Step 7: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_tmux/scripts/claude-diff-review-init.lua
git commit -m "feat(nvim): write a comment per selection in the diff-review popup"
```

---

## Task 3: Edit a comment from the collected list

Add `e` in the list float to re-open the comment buffer for that entry.

**Files:**
- Modify: `~/.local/share/chezmoi/dot_tmux/scripts/claude-diff-review-init.lua`

- [ ] **Step 1: Add the `e` keymap in `M.toggle_list`**

In `M.toggle_list`, immediately AFTER the `<CR>` keymap block (the `jump to ref`
one), add:

```lua
  vim.keymap.set("n", "e", function()
    local idx = vim.fn.line(".")
    if M.collected[idx] then
      M.open_comment_buffer(M.collected[idx].ref, idx)
    end
  end, { buffer = buf, desc = "edit comment" })
```

- [ ] **Step 2: Apply and syntax-check**

```bash
chezmoi apply ~/.tmux/scripts/claude-diff-review-init.lua
nvim --headless -u ~/.tmux/scripts/claude-diff-review-init.lua +qa; echo "exit=$?"
```
Expected: `exit=0`, no errors.

- [ ] **Step 3: Interactive check**

`prefix+e`, collect a couple with comments, `Space l`, move to one, press `e` →
the comment buffer opens prefilled with that comment; edit it; `Space q w` → the
list updates in place (no new entry). `Ctrl-c` while editing leaves it unchanged.

- [ ] **Step 4: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_tmux/scripts/claude-diff-review-init.lua
git commit -m "feat(nvim): edit a collected comment from the list (e)"
```

---

## Task 4: Confirm-on-quit

Add `M.bail` (confirm if anything is collected) and route the `q` mappings
through it.

**Files:**
- Modify: `~/.local/share/chezmoi/dot_tmux/scripts/claude-diff-review-init.lua`

- [ ] **Step 1: Add `M.bail`**

Insert this function immediately ABOVE the `vim.keymap.set("n", "<leader>a", ...)`
keymap block near the bottom of the file:

```lua
-- Quit the popup, sending nothing — but confirm first if comments are collected
-- so an accidental `q` can't silently discard them. Nothing collected quits
-- immediately. (:q!/:qa! remain an un-intercepted force-quit.)
function M.bail()
  if #M.collected == 0 then
    vim.cmd("qa!")
    return
  end
  local choice = vim.fn.confirm(
    "Discard " .. #M.collected .. " collected comment(s)?", "&Yes\n&No", 2)
  if choice == 1 then
    vim.cmd("qa!")
  end
end
```

- [ ] **Step 2: Route the global `q` through `M.bail`**

Replace the global bail keymap:

```lua
vim.keymap.set("n", "q", M.bail, { desc = "bail (confirm if collected)" })
```

- [ ] **Step 3: Route the per-buffer `q` in `on_codediff_ready` through `M.bail`**

In `on_codediff_ready`, replace the `vim.keymap.set("n", "q", ...)` call inside
the window loop:

```lua
    vim.keymap.set("n", "q", M.bail,
      { buffer = buf, desc = "bail (confirm if collected)" })
```

(The comment-buffer and list-float keep their own buffer-local `q` = cancel/close,
which shadow this.)

- [ ] **Step 4: Apply and syntax-check**

```bash
chezmoi apply ~/.tmux/scripts/claude-diff-review-init.lua
nvim --headless -u ~/.tmux/scripts/claude-diff-review-init.lua +qa; echo "exit=$?"
```
Expected: `exit=0`, no errors.

- [ ] **Step 5: Interactive check**

`prefix+e`. With nothing collected, `q` quits immediately. Collect one, then `q`
→ a `Discard 1 collected comment(s)?` prompt; `n`/Enter keeps the popup open,
`y` quits. Inside the comment buffer and the list float, `q` still
cancels/closes (does not prompt-quit the popup).

- [ ] **Step 6: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_tmux/scripts/claude-diff-review-init.lua
git commit -m "feat(nvim): confirm before quitting the popup with collected comments"
```

---

## Task 5: Update help text and header docstring

**Files:**
- Modify: `~/.local/share/chezmoi/dot_tmux/scripts/claude-diff-review-init.lua`

- [ ] **Step 1: Update the header KEYS block**

Replace these three header-comment lines (lines 8-13 region):

```
--   <leader>a       collect hunk under cursor (normal) / selection (visual)
--                   — working-tree (right) side only
--   <leader>l       toggle collected list  (dd remove · <CR> jump · q close)
--   <leader>z       jump to another git repo (zoxide picker)
--   <leader><CR>    confirm: paste refs to the origin pane (errors if not Claude)
--   q  /  :q        bail — quit, send nothing
```

with:

```
--   <leader>a       comment a hunk (normal) / selection (visual), right side
--                   — opens a comment buffer: <leader>qw save · <C-c>/q cancel
--   <leader>l       toggle collected list (dd remove · <CR> jump · e edit · q close)
--   <leader>z       jump to another git repo (zoxide picker)
--   <leader><CR>    confirm: compile comments + paste to origin pane (if Claude)
--   q  /  :q        bail — quit (confirms if comments collected)
```

- [ ] **Step 2: Update the `M.show_help` lines table**

Replace these entries in the `lines` table inside `M.show_help`:

```lua
    " <leader>a     collect hunk (normal) / selection (visual)",
    "               — working-tree (right) side only",
    " <leader>l     toggle collected list (dd remove · CR jump · q close)",
    " <leader>z     jump to another git repo (zoxide)",
    " <leader><CR>  confirm: paste refs to origin pane",
    " q / :q        bail — quit, send nothing",
```

with:

```lua
    " <leader>a     comment a hunk (normal) / selection (visual), right side",
    "               buffer: <leader>qw save · <C-c>/q cancel",
    " <leader>l     collected list (dd remove · CR jump · e edit · q close)",
    " <leader>z     jump to another git repo (zoxide)",
    " <leader><CR>  confirm: compile comments + paste to origin pane",
    " q / :q        bail — quit (confirms if comments collected)",
```

- [ ] **Step 3: Apply and syntax-check**

```bash
chezmoi apply ~/.tmux/scripts/claude-diff-review-init.lua
nvim --headless -u ~/.tmux/scripts/claude-diff-review-init.lua +qa; echo "exit=$?"
```
Expected: `exit=0`, no errors.

- [ ] **Step 4: Interactive check**

`prefix+e`, press `Space ?` → the cheatsheet shows the comment-buffer keys, the
list `e` edit key, and the confirm-on-quit note.

- [ ] **Step 5: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_tmux/scripts/claude-diff-review-init.lua
git commit -m "docs(nvim): update diff-review popup help for comments"
```

---

## Task 6: End-to-end verification and integration

No new code. Verifies the whole flow — especially the bracketed-paste delivery,
the one real unknown — then merges and pushes.

- [ ] **Step 1: Full manual run**

From a Claude pane, in a repo with changes:
1. `prefix+e` → land in the right pane.
2. `Space a` on a hunk → comment buffer → type a multi-line comment → `Space q w`.
3. Visual-select a range → `Space a` → comment → `Space q w`.
4. `Space a` → `Ctrl-c` → cancelled (nothing added).
5. `Space l` → list shows `ref │ comment-preview`; `e` edits one; `dd` removes
   one; `<CR>` jumps.
6. `Space <CR>` → the Claude prompt receives:
   ```
   Please address these review comments:

   ## <ref>
   <comment>

   ## <ref>
   <comment>
   ```
   multi-line, **not** submitted.
7. Reopen, collect one, press `q` → confirm prompt; `n` keeps it, `y` quits.

- [ ] **Step 2: Decide the delivery path**

If Step 1.6 pasted cleanly into the Claude prompt without submitting, keep the
bracketed-paste implementation. If it misbehaved (submitted early, or mangled),
switch `confirm`'s delivery to the temp-file reference fallback: keep the
`tmpfile`, skip `delete`, and instead
`vim.fn.system({ "tmux", "send-keys", "-t", pane, "-l", "Review comments in @" .. tmpfile })`.
Re-run Step 1.6 to confirm, then commit the change:
```bash
cd ~/.local/share/chezmoi
git add dot_tmux/scripts/claude-diff-review-init.lua
git commit -m "fix(nvim): deliver review comments via temp-file reference"
```
(Skip this step entirely if bracketed paste worked.)

- [ ] **Step 3: Headless gate**

```bash
nvim --headless -u ~/.tmux/scripts/claude-diff-review-init.lua +qa; echo "exit=$?"
```
Expected: `exit=0`, no errors.

- [ ] **Step 4: Merge and push**

```bash
cd ~/.local/share/chezmoi
git checkout main
git merge --no-ff feat/codediff-popup-review-comments -m "Merge review-comments for diff-review popup"
git push origin main
git branch -d feat/codediff-popup-review-comments
```

---

## Self-review notes

- **Spec coverage:** records model (T1), comment buffer + collect routing (T2),
  list `e` edit (T3), compile + bracketed-paste delivery (T1 with T6 fallback),
  confirm-on-quit (T4), docs (T5), end-to-end incl. paste verification (T6).
- **No placeholders:** every code block is complete; the only branch is T6 Step 2
  (keep bracketed paste vs. temp-file fallback), with full code for the fallback.
- **Naming consistency:** `M.collected` records use `.ref`/`.comment` everywhere;
  `M.open_comment_buffer(ref, existing_index)`, `M.bail`, `M.jump_to(ref)`,
  `M.refresh_list`, `M.toggle_list`, `M.confirm` match across tasks and the
  existing file.
