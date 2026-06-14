# Per-selection review comments in the diff-review popup

**Date:** 2026-06-14
**Status:** Approved, ready for planning
**Builds on:** `2026-06-14-codediff-diff-review-popup-design.md` (the codediff popup)

## Goal

Make the `prefix+e` diff-review popup work like a VSCode review pass: select a
hunk or a visual range, write a comment on it, repeat across files, then on
`Space <CR>` compile all the comments into one message pasted into the Claude
pane. Today the popup only collects bare `path:start-end` refs and pastes them
space-joined; this adds a comment to each ref and a readable compiled output.

Also adds a **confirm-on-quit** guard so an accidental `q` doesn't silently
discard collected comments.

All changes are in the single standalone init
`dot_tmux/scripts/claude-diff-review-init.lua` (chezmoi source). No new files.

## Current behaviour (what changes)

- `add_ref(s, e)` pushes the string `"path:start-end"` onto `M.collected`.
- `collect_hunk` / `collect_visual` (mapped to `<leader>a` in normal/visual)
  compute the range and call `add_ref`.
- `toggle_list` (`<leader>l`) shows `M.collected` as plain lines; `dd` removes,
  `<CR>` jumps via `M.jump_to`, `q` closes.
- `M.jump_to(ref)` parses `path` and start line out of the ref string.
- `confirm` (`<leader><CR>`) joins `M.collected` with spaces and pastes via
  `tmux send-keys -t <pane> -l <refs>` (single line), then `qa!`.
- `q` (global, and re-asserted on codediff buffers by `on_codediff_ready`) maps
  straight to `qa!` (bail, send nothing).

## Design

### 1. Data model: refs become `{ref, comment}` records

`M.collected` changes from a list of strings to a list of records:

```lua
{ ref = "path:start-end", comment = "" }   -- comment may be empty
```

Every consumer updates to the record shape: `add_ref`, `list_lines`,
`refresh_list`, `jump_to` (reads `entry.ref`), `confirm` (reads both), and the
list-float `dd`/`<CR>`/`e` handlers.

### 2. Collect -> comment flow

`<leader>a` (hunk or visual) computes the ref exactly as today, then opens a
**floating scratch comment buffer** instead of immediately storing a bare ref:

- The float is a `nofile`/`wipe` scratch buffer, ~half-width, centered or near
  the cursor, titled with the ref, e.g. `─ src/auth.py:10-15 ─`.
- It opens in **insert mode** so the user types immediately. Multi-line allowed.
- A pending `{ref, comment}` is only committed to `M.collected` on save.

Comment-buffer keymaps (buffer-local):

- **`<leader>qw`** (Space q w — mirrors the user's normal `:w`), normal mode:
  **save** — read the buffer's lines as the comment, push `{ref, comment}` to
  `M.collected` (empty comment is allowed = a bare pointer), `vim.notify`
  `+ collected (N): ref`, close the float.
- **`<C-c>`** (insert and normal): **cancel** — discard the pending ref, close
  the float, store nothing.
- **`q`** (normal mode): also cancel. This is required for safety: the global
  `q -> qa!` (or its confirm wrapper) would otherwise fire inside the comment
  buffer and try to quit the whole popup. Buffer-local `q` shadows it.

The pending ref lives in a local (e.g. `M._pending = { ref = ... }`) captured by
the save/cancel closures, not in `M.collected`, so a cancel leaves no trace.

### 3. Collected list (`<leader>l`) shows and edits comments

`list_lines` renders one line per entry:

```
src/auth.py:10-15  │ this should handle the nil case
src/utils.py:3     │ (no comment)
```

The ref is left-aligned/padded; the comment is its first line, truncated to the
float width; `(no comment)` when empty. The list float height tracks
`#M.collected` as today.

List-float keymaps (buffer-local), keyed by cursor line -> entry index:

- `dd` — remove that entry (existing behaviour, new shape).
- `<CR>` — jump to that entry's ref (existing `M.jump_to`, reads `entry.ref`).
- **`e`** — re-open the comment scratch buffer pre-filled with that entry's
  comment; saving updates the entry in place (edit, not append); cancel leaves it
  unchanged. Reuses the same comment-buffer function, parameterised by an
  optional existing index.

### 4. Compile + deliver on `<leader><CR>`

`confirm` builds the message in the approved format:

```
Please address these review comments:

## src/auth.py:10-15
this should handle the nil case

## src/utils.py:3
typo: recieve -> receive
```

- Preamble line: `Please address these review comments:` then a blank line.
- Each entry: `## <ref>`, then the comment lines, then a blank line. Entries with
  an empty comment render as just the `## <ref>` header.

Delivery must be **multi-line-safe**, so it cannot use the current
`send-keys -l` (newlines would submit at each line in the Claude TUI). Instead:

1. Write the compiled text to a temp file (`vim.fn.tempname()`).
2. `tmux load-buffer <tmpfile>` (loads into a tmux paste buffer).
3. `tmux paste-buffer -p -d -t <ORIGIN_PANE>` — `-p` uses **bracketed paste** so
   the Claude TUI treats it as pasted content (multi-line inserted into the
   prompt, **not submitted**); `-d` deletes the tmux buffer after.
4. Remove the temp file. Then `qa!`.

The Claude-pane verification (`is-claude-pane.sh` on the origin pane's tty) and
the empty-collection guard stay exactly as today. As before, it **pastes without
submitting**, so the user can edit/add framing and press Enter themselves.

Fallback (if bracketed paste misbehaves against the Claude TUI during
implementation testing): keep the temp file and paste a single line referencing
it, e.g. `Review comments in @<tmpfile>` via `send-keys -l`. The plan's verify
step decides which path ships.

### 5. Confirm-on-quit

Introduce `M.bail()`:

- If `#M.collected == 0`, `qa!` immediately (nothing to lose).
- Otherwise prompt with `vim.fn.confirm("Discard N collected comment(s)?",
  "&Yes\n&No", 2)` (default No); `qa!` only on Yes, else return (stay open).

Route the quit key through it:

- The global `q` mapping and the per-buffer `q` re-asserted in `on_codediff_ready`
  both call `M.bail()` instead of `vim.cmd("qa!")`.
- The comment-buffer and list-float keep their own buffer-local `q` (cancel /
  close), which shadow the bail mapping there.
- `confirm`'s own success path still `qa!`s directly (sending then quitting is
  intentional, no prompt).
- `:q!` / `:qa!` remain un-intercepted as a deliberate no-confirm force-quit.

### 6. Docs

Update the header docstring and the `<leader>?` cheatsheet: describe the comment
buffer (`Space a` -> write -> `Space q w` save / `C-c` cancel), the list `e` edit
key, and that `q` now confirms when comments are collected.

## File structure

One file, `dot_tmux/scripts/claude-diff-review-init.lua`. New/changed units:

- `M.collected` shape (records) — touches the collection engine.
- `M.open_comment_buffer(ref, existing_index?)` — NEW: the scratch comment float
  + save/cancel keymaps; handles both new collection and list edit.
- `add_ref` -> folded into the comment-buffer save path.
- `collect_hunk` / `collect_visual` — compute ref, then call
  `M.open_comment_buffer(ref)`.
- `list_lines` / `toggle_list` — record shape + `e` keymap.
- `M.jump_to` — read `entry.ref`.
- `confirm` — compile records, deliver via bracketed paste.
- `M.bail` — NEW: confirm-on-quit; wired into `q` mappings.

## Risks and mitigations

- **Bracketed-paste into the Claude TUI** is the main unknown. Mitigation: the
  plan verifies it interactively; temp-file `@path` reference is the fallback.
- **`q` inside the comment/list floats accidentally quitting the popup.**
  Mitigation: buffer-local `q` in both floats shadows the global bail.
- **Edit vs append in the list.** Mitigation: `open_comment_buffer` takes an
  optional index; present -> replace that entry, absent -> append.

## Verification

- Syntax gate: `nvim --headless -u <init> +qa` exits 0.
- Manual (in a repo with changes, from a Claude pane):
  1. `Space a` on a hunk -> comment buffer opens in insert; type 2 lines;
     `Space q w` -> `+ collected (1)`.
  2. Visual-select lines, `Space a`, `C-c` -> cancelled, nothing collected.
  3. `Space a`, save empty -> collected with `(no comment)`.
  4. `Space l` -> list shows refs + comment previews; `e` edits one; `dd`
     removes one; `<CR>` jumps.
  5. `Space <CR>` -> the compiled `Please address these review comments:` block
     appears in the Claude prompt (multi-line, not submitted).
  6. With comments collected, press `q` -> confirm prompt; No keeps the popup,
     Yes quits. With nothing collected, `q` quits immediately.
