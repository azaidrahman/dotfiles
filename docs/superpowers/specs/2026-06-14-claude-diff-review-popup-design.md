# Claude Diff-Review Popup — Design

**Date:** 2026-06-14
**Status:** Approved for planning

## Goal

A tmux popup, triggered from inside a Claude Code pane, that opens a small
isolated nvim showing Claude's working-tree changes. You navigate changed files
and hunks, collect a set of hunk references, and on confirm those references are
pasted back into the originating Claude Code prompt so you can talk about them.
The popup only activates when the triggering pane is running Claude Code, and you
can always bail out cleanly without sending anything.

This replaces the heavier lazygit flow for the specific task of "review what
Claude just changed and reference it in conversation."

## Scope

- **In:** working-tree diff (working tree vs `HEAD`) only.
- **Out:** proposed/pre-apply diffs, arbitrary commit/branch diffs, hunk staging.
- **Pasted payload:** plain `path:Lstart-Lend` references only — no hunk text.
  User adds their own prose after the refs land.

## Components

### 1. tmux keybinding + detection wrapper

- Bind `prefix + e` (verified free in `dot_tmux/conf.d/keys.conf`; prefix is
  `C-Space`) to `run-shell` a wrapper script.
- Wrapper takes the active pane's **tty** (`#{pane_tty}`) and checks whether any
  process on that tty is `claude`:
  `ps -t <tty> -o command= | grep -q '[c]laude'`.
  - **Validated (2026-06-14):** every tmux pane has a unique tty shared by all its
    processes, so this is reliable. A descendant-pid walk was rejected — claude is
    often several levels below the pane's shell pid (e.g. `zsh → chezmoi cd → zsh
    → claude`), so a shallow `pgrep -P` misses it.
  - **Not found:** silent exit. Optional `display-message "not a claude pane"`
    line, left in but easy to comment out.
  - **Found:** open the popup, passing into its environment:
    - `CLAUDE_PANE` = origin pane id (`#{pane_id}`), captured before the popup opens.
    - `REPO` = `#{pane_current_path}`.

### 2. The popup (isolated nvim)

- `tmux display-popup -E` launches nvim with a **dedicated init file** (e.g.
  `-u <review-init.lua>`), NOT the user's normal config. This guarantees zero
  interference with the main nvim setup and a fast boot loading only diffview +
  the collect keymaps.
- On open it runs `DiffviewOpen` against the working tree (vs `HEAD`) in `REPO`.
- Navigation uses diffview defaults: file panel, `<Tab>`/`<S-Tab>` next/prev
  file, `]c`/`[c` hunk nav, `g?` help.

### 3. Hunk collection

- In-memory Lua list of `path:Lstart-Lend` strings (path relative to `REPO`).
- `<leader>a` (normal mode) — collect the hunk under the cursor; line range
  derived from diffview's hunk boundaries. Echoes `+ collected (N)`.
- `<leader>a` (visual mode) — collect exactly the visually-selected line range.
  - Restricted to the **right** (current working-tree) buffer, whose line numbers
    match the real file. In the left (`HEAD`) buffer it refuses with a brief echo
    (`select in the current-file side`) rather than collecting wrong line numbers.
- `<leader>l` — toggle a **lightweight floating scratch buffer** listing all
  collected refs, one per line.
  - `dd` in the float removes that entry from the list.
  - `<CR>` in the float jumps to that hunk in the diff.
  - `q` closes the float.
  - Deliberately a scratch float, not `setqflist`, to avoid polluting the global
    quickfix list.

### 4. Handoff (paste refs)

- `<leader><CR>` — confirm:
  1. Join collected refs into a **single space-separated line**:
     `fileA.ts:10-20 fileB.ts:30-40`.
  2. `tmux send-keys -t $CLAUDE_PANE -l "<refs>"` — literal (`-l`), **no trailing
     Enter**, so the cursor lands after the refs in Claude's prompt and the user
     types their question (or hits Enter) themselves.
  3. Quit the popup.
- **Why single-line (validated 2026-06-14):** a raw newline sent via `send-keys`
  is delivered as Enter, which submits the prompt in Claude's TUI — multi-line
  refs would fire off after the first line. A single space-separated line keeps
  the refs readable and makes `send-keys -l` safe with no submit risk.
- **Optional multi-line mode (one ref per line):** requires bracketed paste —
  `load-buffer` then `paste-buffer -p -t $CLAUDE_PANE`. tmux only emits the
  bracketed-paste markers (`ESC[200~`…`ESC[201~`) when the receiving app has
  enabled bracketed-paste mode; Claude's TUI does, but confirm against a live
  Claude prompt before relying on it. Default to single-line unless the user
  asks for one-per-line.
- **Bail:** `:q` / `q` in diffview quits the popup and sends nothing.

## Keymap summary (inside popup only — isolated init)

| Key | Action | Collision check |
|-----|--------|-----------------|
| `<leader>a` (n) | collect hunk under cursor | free (diffview unused) |
| `<leader>a` (v) | collect visual line range (right buffer only) | free |
| `<leader>l` | toggle collected-list float | free |
| `<leader><CR>` | confirm & paste refs to Claude pane | free (avoids diffview's `<leader>c*`) |
| `q` / `:q` | bail, send nothing | diffview default |

Leader is `<Space>`. Diffview occupies `<leader>e`, `<leader>b`, and
`<leader>c{o,t,b,a,O,T,B,A}` — all avoided.

## Flow

```
prefix + e  (in tmux)
   │
   ▼
run-shell wrapper ── check active pane's tty for a `claude` process
   ├─ not found → silent no-op (optional message)
   └─ found ↓
        display-popup -E  (env: CLAUDE_PANE, REPO)
            │
            ▼
        nvim -u review-init.lua  → DiffviewOpen (working tree vs HEAD)
            │  navigate files (panel) + hunks (]c/[c)
            │  <leader>a collect → list;  <leader>l inspect/prune float
            │
            ├─ <leader><CR>  confirm → send-keys refs to CLAUDE_PANE, quit
            └─ :q / q        bail → quit, nothing sent
```

## Files (chezmoi-managed)

- `dot_tmux/conf.d/keys.conf` — add `bind e run-shell '<wrapper>'`.
- `dot_tmux/scripts/executable_claude-diff-review.sh` — detection wrapper +
  popup launch.
- nvim review init, e.g. `dot_config/nvim/<path>/claude-diff-review.lua` (exact
  location TBD in plan) — dedicated init: diffview + collect/list/confirm keymaps.

## Error handling

- Not a Claude pane → silent no-op (optional message).
- No working-tree changes → diffview opens empty; popup still works, confirm with
  zero refs sends nothing (or no-ops with a brief echo).
- Origin pane closed before confirm → `send-keys` fails harmlessly; popup quits.

## Validation results (2026-06-14, spike on this machine)

- **tty detection — PASS.** `ps -t <pane_tty> -o command= | grep -q '[c]laude'`
  correctly identified the Claude pane; sibling panes showed `zsh` and did not match.
- **descendant-pid walk — REJECTED.** Claude ran 3 levels below the pane shell pid
  (`zsh → chezmoi cd → zsh → claude`); a shallow `pgrep -P` found nothing. Drove the
  switch to tty-based detection.
- **multi-line `send-keys` — CONFIRMED RISK.** A raw `\n` is delivered as Enter and
  submits Claude's prompt. Resolved by pasting refs as a single space-separated line.
- **`paste-buffer -p` bracketing — CONDITIONAL.** Raw-byte capture against `cat`
  showed content preserved but NO `ESC[200~`/`ESC[201~` markers, because tmux only
  emits them when the receiving app enabled bracketed-paste mode. Must be re-confirmed
  against a live Claude prompt before the optional multi-line mode is trusted.

### Open spike for the implementation plan

- Confirm diffview's right-panel `line('.')` and visual `'<`/`'>` marks return true
  working-file line numbers (expected: yes — it is a real file buffer).

## Testing

- Manual: edit a file via Claude, `prefix + e`, collect 2 hunks across files,
  inspect float, remove one, confirm, verify the surviving ref pastes into the
  prompt with cursor after it and no auto-submit.
- Negative: trigger `prefix + e` from a plain shell pane → no popup.
- Bail: open popup, `:q` → nothing pasted.
