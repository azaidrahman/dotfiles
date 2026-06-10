# Nvim/tmux Deduplication — tmux-aware Neovim Config

**Date:** 2026-06-10
**Status:** Approved

## Problem

The Neovim config duplicates capabilities that tmux already owns (terminals,
git UI popup, workspace switching). The user works tmux-first: tmux
resurrect/continuum owns sessions, tmux windows are the workspace unit, and
tmux popups/splits are the terminal surface. However, nvim is sometimes
launched outside tmux (bare Ghostty, remote hosts without tmux), where those
"redundant" features are genuinely useful.

## Decision

Gate the redundant nvim features on a runtime check: **active when nvim runs
outside tmux, disabled when inside tmux**. Nothing is deleted; existing code
is wrapped in conditionals so the standalone path keeps current behavior
exactly. `plugins_archive/` is left untouched.

## Core mechanism

New tiny module, single source of truth:

```lua
-- lua/zaid/core/env.lua
local M = {}
M.in_tmux = vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
return M
```

- Lazy plugin specs / keys: use `enabled = not env.in_tmux` or conditional
  key tables.
- Plain keymaps and commands: `if not env.in_tmux then ... end`.
- The flag is evaluated once at startup. An nvim process started inside a
  tmux pane remains inside that pane even if the client detaches, so startup
  evaluation is correct.

## Gated features (hidden inside tmux, active standalone)

| Feature | Location | Tmux replacement |
|---|---|---|
| Floating terminal `<space>tt` + `pop_terminal()` / `:Terminalpop` | `dot_config/nvim/lua/zaid/core/commands.lua`, `core/keymaps.lua` | tmux splits / `display-popup` |
| Lazygit `<leader>lg`, `<leader>gl` (snacks) | `dot_config/nvim/lua/zaid/plugins/snacks.lua` | new `prefix+G` popup |
| Vim tab keymaps `<leader>to/tx/tn/tp/tf` | `dot_config/nvim/lua/zaid/core/keymaps.lua` | tmux windows + `prefix+f` TV picker |

## Tmux-side addition

In `dot_tmux/conf.d/keys.conf`:

```tmux
# Lazygit popup in current pane's directory (G — g is tmux-jump)
bind G display-popup -d "#{pane_current_path}" -w 90% -h 90% -E "lazygit"
```

## Explicitly untouched

- `vim-tmux-navigator` — the bridge; loads in both modes (it degrades
  gracefully outside tmux, navigating vim splits only).
- neogit + gitsigns — in-buffer git operations, editor-domain, not redundant.
- snacks pickers, fff, harpoon, oil, lualine, incline, trouble — editor-domain.
- Session management — already settled: `auto-session` archived; tmux
  resurrect/continuum owns it.
- Split resizing/navigation — already settled: `smart-splits` archived.
- `plugins_archive/`, stray `dot_DS_Store` files — out of scope per user.

## Testing

1. Inside tmux: `<space>tt`, `<leader>lg`, `<leader>gl`, `<leader>to/tx/tn/tp/tf`
   are unmapped (no-op or default vim behavior); `prefix+G` opens lazygit
   popup in the pane's directory.
2. Outside tmux (bare terminal): all gated features work exactly as today.
3. `nvim --headless "+lua print(require('zaid.core.env').in_tmux)" +q` inside
   and outside tmux returns `true`/`false` respectively.
4. Chezmoi: `chezmoi diff` shows only intended files; apply and reload tmux
   config cleanly (`prefix+r`).
