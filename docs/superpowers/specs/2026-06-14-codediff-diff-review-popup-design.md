# Swap the Claude diff-review popup from diffview to codediff

**Date:** 2026-06-14
**Status:** Approved, ready for planning
**Supersedes the diff engine in:** `2026-06-14-claude-diff-review-popup-design.md` (collection/paste workflow unchanged)

## Goal

The `prefix+e` tmux popup is a fast, good-looking diff viewer for reviewing the
working tree and shipping hunk references to the Claude pane. diffview.nvim is
heavier than this flow needs (it is really a git-extension UI) and its look
required a pile of custom theming workarounds. Replace the popup's diff engine
with [esmuellert/codediff.nvim](https://github.com/esmuellert/codediff.nvim) (a
VSCode-style, C-backed diff with two-tier highlighting), lean on its built-in
auto-adapting theme, and keep the collect-hunks-and-paste-to-Claude workflow
exactly as it is today.

Non-goals (explicitly out of scope, decided during brainstorming):
- The earlier asks for a custom statusline showing the current file and for
  always-visible +/- line deltas. Dropped. codediff's own UI is good enough.
- Any change to neogit or the main-config git workflow. diffview stays installed
  as a neogit dependency.

## Context: how the popup works today

- `prefix+e` -> `~/.tmux/scripts/claude-diff-review.sh` -> `display-popup` running
  `nvim -u ~/.tmux/scripts/claude-diff-review-init.lua`.
- The init (chezmoi source: `dot_tmux/scripts/claude-diff-review-init.lua`)
  prepends `plenary.nvim` + `diffview.nvim` to the runtimepath, loads NONE of the
  user's normal config, applies shared look-and-feel via
  `require("zaid.popup_ui").apply()`, opens diffview on `VimEnter`, and layers a
  collect-and-paste workflow on top.
- The collection workflow: `<leader>a` collects the hunk (or visual selection)
  under the cursor on the working-tree side as a `path:start-stop` ref;
  `<leader>l` toggles a float listing collected refs (`dd` remove, `<CR>` jump,
  `q` close); `<leader>z` switches repo via a zoxide picker; `<leader><CR>`
  confirms, verifying the origin pane is Claude and pasting the space-joined refs
  with `tmux send-keys -l`; `q`/`:q` bails sending nothing.

## What codediff gives us (from its README/API)

- `:CodeDiff` with no args opens a changed-files explorer for the working tree
  (equivalent to diffview's working-tree-vs-HEAD view).
- Explorer panel with `]f`/`[f` file navigation and `<CR>` to select a file.
- The working-tree side is a real, on-disk, editable buffer with normal line
  numbers; the git side is a read-only in-memory buffer.
- Side-by-side (default) or inline layout; auto-adapts diff colors to the active
  colorscheme's background.
- User autocmds: `CodeDiffOpen`, `CodeDiffClose`, `CodeDiffFileSelect` (carries
  `path`, `status`).
- Default keymaps include `q` (quit view), `]c`/`[c` (hunk), `]f`/`[f` (file).
  It does NOT bind `<space>`.
- The prebuilt C binary auto-downloads on first use (needs curl/wget + network).

## Approach

Approach C from brainstorming: drop the popup's custom theming entirely and rely
on the default nvim colorscheme plus codediff's auto-adapt. This removes
`popup_ui.lua` and all of its workarounds, leaving a much smaller init.

### 1. Install codediff, keep diffview

- New lazy plugin spec `dot_config/nvim/lua/zaid/plugins/codediff.lua` with
  `{ "esmuellert/codediff.nvim", cmd = "CodeDiff" }`.
- diffview.nvim is left exactly as-is (neogit dependency in `gitstuff.lua`).
- Binary pre-warm: the plan checks whether codediff exposes a download/build
  function. If it does, wire it as a lazy `build` step so the binary lands at
  install time. If it does not, accept a one-time download on first popup launch
  (acceptable: the user normally has curl + network).

### 2. Remove popup_ui.lua

`dot_config/nvim/lua/zaid/popup_ui.lua` has exactly one consumer (this popup;
confirmed by grep), so it is deleted. The init keeps only `termguicolors` and
`background=dark`; the default colorscheme + codediff auto-adapt handle the look.
Removed along with it: tokyonight setup, the lualine statusline, the tmux-pane
background blend, and the markdown-heading highlight workaround (which only
existed to fight tokyonight + diffview).

### 3. Rewrite the diffview-specific parts of the init

Change in `dot_tmux/scripts/claude-diff-review-init.lua`:

- **rtp:** prepend `codediff.nvim` instead of `plenary.nvim` + `diffview.nvim`.
  The plan verifies plenary is not needed by the remaining code paths (snacks
  zoxide picker does not require it).
- **setup:** replace the diffview setup (and its `<space>`-disable block, no
  longer needed) with `require("codediff").setup({...})` (side-by-side default,
  explorer on left). Keep it minimal.
- **open:** `VimEnter` -> `vim.cmd("CodeDiff")` instead of
  `require("diffview").open()`. Keep the headless guard
  (`#vim.api.nvim_list_uis() > 0`).
- **q bail:** codediff binds buffer-local `q` to close its own view, which would
  shadow the global `q -> qa!`. Rebind `q -> qa!` on codediff's buffers, mirroring
  the current `Diffview*`-filetype autocmd. The exact filetype(s) / event are
  discovered in the introspection task.
- **switch_repo:** replace `require("diffview").close()` with codediff's teardown
  (close command or tab close, confirmed during introspection), then
  `vim.cmd("CodeDiff")`. Ref-clearing behavior unchanged.
- **help + comments:** update the header docstring, the `<leader>?` cheatsheet,
  and nav hints (`<Tab>/<S-Tab>` -> `]f/[f`; drop diffview-only keys such as
  `<leader>e`/`<leader>b`/`g?`).

### 4. Keep the collection engine unchanged (the send-to-Claude flow)

These are plugin-agnostic and stay as-is, so paste-to-Claude keeps working
identically:

- `is_worktree_side()` - still correct: the real guard is
  `filereadable(name) == 1`, which holds because codediff keeps the working-tree
  side a real file. The `diffview://` URI early-return becomes a generic comment
  (optionally also match codediff's read-only scheme, but `filereadable` is the
  source of truth).
- `hunk_range_at()` - parses `git diff -U0 HEAD`, independent of the diff engine.
- `add_ref()`, `list_lines()`, `refresh_list()`, `toggle_list()` (the collected
  float), `confirm()` (verifies origin pane is Claude, pastes refs), `jump_repo()`
  / `switch_repo()` zoxide flow - unchanged except the diffview close call noted
  above.

### 5. Reimplement jump_to for codediff (best-effort)

The collected-list `<CR>` jump is the only genuinely new logic. The current
version reaches into `diffview.lib` (`get_current_view()`,
`ordered_file_list()`, `set_file()`). codediff has no documented equivalent, so:

1. The plan's FIRST task installs codediff and inspects its source for an
   internal select-file-by-path function (e.g. in `lua/codediff/ui` or
   `lua/codediff/core`). If found, `jump_to` calls it, then schedules
   `vim.fn.cursor(line, 1)`.
2. Fallback if no such API exists: drive the explorer buffer directly - focus the
   explorer window, find the row matching the ref's path, feed `<CR>` to select,
   then schedule the cursor jump.

This is explicitly best-effort (user decision): correct for the common case, and
if codediff's internals shift it degrades to a no-op rather than breaking the
popup.

## Files touched

- `dot_config/nvim/lua/zaid/plugins/codediff.lua` - NEW lazy spec.
- `dot_tmux/scripts/claude-diff-review-init.lua` - MODIFY (rtp, setup, open,
  close, q-rebind, jump_to, help/comments).
- `dot_config/nvim/lua/zaid/popup_ui.lua` - DELETE (orphaned).
- diffview.nvim / `gitstuff.lua` - UNCHANGED.

All paths are chezmoi-managed: edits land in the chezmoi source, then
`chezmoi apply` writes them to `~`. The chezmoi-sync skill handles the final
commit/push.

## Risks and mitigations

- **codediff internals for jump_to / close / filetype are not in the README.**
  Mitigated by making source introspection the first plan task; later tasks build
  on the discovered facts.
- **First-launch binary download could stall an offline popup.** Mitigated by the
  optional `build`-time pre-warm; otherwise a known, one-time, online-only cost.
- **Default-colorscheme look might be plainer than the old tuned palette.**
  Accepted by the user (Approach C). codediff's auto-adapt still renders diffs
  cleanly on the default theme.

## Verification

- Syntax check: `nvim -u <init> +qa` exits 0 (VimEnter guard skips opening in
  headless).
- Manual: edit a file via Claude, `prefix+e`, confirm codediff opens the
  working-tree explorer; navigate files with `]f`/`[f`; collect a hunk
  (`<leader>a`) and a visual selection on the working-tree side; toggle the list
  (`<leader>l`), remove with `dd`, jump with `<CR>`; `<leader>z` switches repo and
  clears refs; `<leader><CR>` pastes the refs into the Claude pane; `q` bails
  sending nothing.
- Negative: `<leader>a` on the read-only git side warns and collects nothing.
