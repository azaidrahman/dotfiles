# Tmux-Aware Nvim Dedup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gate redundant nvim features (floating terminal, lazygit, tab keymaps) so they are active only when nvim runs outside tmux, and add a tmux `prefix+G` lazygit popup.

**Architecture:** A new `zaid.core.env` module is the single source of truth for the `in_tmux` flag and exposes two decorator-style helpers — `when_standalone(fn)` for imperative code and `standalone_keys(keys)` for lazy.nvim key specs. Every gated site calls a helper; the `TMUX` check appears exactly once in the codebase. Spec: `docs/superpowers/specs/2026-06-10-nvim-tmux-dedup-design.md`.

**Tech Stack:** Lua (Neovim 0.10+, lazy.nvim), tmux conf, chezmoi-managed dotfiles.

**Repo context:** All paths are relative to the chezmoi source dir `~/.local/share/chezmoi`. Nvim reads the *applied* config at `~/.config/nvim`, so every verification step runs `chezmoi apply` first. The `TMUX` env var is simulated in verification commands (`TMUX=` for standalone, `TMUX=/tmp/fake,1,0` for inside-tmux) — no real tmux server needed. Note: nvim's leader is space, so `<leader>to` is typed as `<Space>to`; `maparg()` lookups use the literal `' to'` form via `vim.keycode`.

---

### Task 1: Create `env.lua` with the gate helpers

**Files:**
- Create: `dot_config/nvim/lua/zaid/core/env.lua`

- [ ] **Step 1: Write the module**

```lua
-- Runtime environment detection. Single source of truth for tmux-aware gating:
-- features tmux already owns (terminals, lazygit popup, workspace switching)
-- only activate when nvim runs standalone.
local M = {}

M.in_tmux = vim.env.TMUX ~= nil and vim.env.TMUX ~= ""

-- Run fn only when nvim is standalone (outside tmux).
function M.when_standalone(fn)
	if not M.in_tmux then
		fn()
	end
end

-- Return the given lazy.nvim key specs when standalone, {} inside tmux.
function M.standalone_keys(keys)
	return M.in_tmux and {} or keys
end

return M
```

- [ ] **Step 2: Apply and verify the flag in both modes**

Run:
```bash
chezmoi apply ~/.config/nvim
TMUX= nvim --headless "+lua print('in_tmux=' .. tostring(require('zaid.core.env').in_tmux))" +q 2>&1
TMUX=/tmp/fake,1,0 nvim --headless "+lua print('in_tmux=' .. tostring(require('zaid.core.env').in_tmux))" +q 2>&1
```
Expected: first prints `in_tmux=false`, second prints `in_tmux=true`.

- [ ] **Step 3: Verify the helpers in both modes**

Run:
```bash
TMUX= nvim --headless "+lua local e=require('zaid.core.env'); local ran=false; e.when_standalone(function() ran=true end); print('ran=' .. tostring(ran) .. ' keys=' .. #e.standalone_keys({1,2}))" +q 2>&1
TMUX=/tmp/fake,1,0 nvim --headless "+lua local e=require('zaid.core.env'); local ran=false; e.when_standalone(function() ran=true end); print('ran=' .. tostring(ran) .. ' keys=' .. #e.standalone_keys({1,2}))" +q 2>&1
```
Expected: first prints `ran=true keys=2`, second prints `ran=false keys=0`.

- [ ] **Step 4: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_config/nvim/lua/zaid/core/env.lua
git commit -m "feat(nvim): add core.env with tmux-aware gating helpers"
```

---

### Task 2: Gate the vim tab keymaps

**Files:**
- Modify: `dot_config/nvim/lua/zaid/core/keymaps.lua:80-85`

- [ ] **Step 1: Replace the tab keymap block**

In `dot_config/nvim/lua/zaid/core/keymaps.lua`, replace:

```lua
-- tab stuff
vim.keymap.set("n", "<leader>to", "<cmd>tabnew<CR>", { desc = "Open new tab" })
vim.keymap.set("n", "<leader>tx", "<cmd>tabclose<CR>", { desc = "Close current tab" })
vim.keymap.set("n", "<leader>tn", "<cmd>tabn<CR>", { desc = "Go to next tab" })
vim.keymap.set("n", "<leader>tp", "<cmd>tabp<CR>", { desc = "Go to previous tab" })
vim.keymap.set("n", "<leader>tf", "<cmd>tabnew %<CR>", { desc = "Open current buffer in new tab" })
```

with:

```lua
-- tab stuff (standalone only — tmux windows are the workspace unit inside tmux)
require("zaid.core.env").when_standalone(function()
    vim.keymap.set("n", "<leader>to", "<cmd>tabnew<CR>", { desc = "Open new tab" })
    vim.keymap.set("n", "<leader>tx", "<cmd>tabclose<CR>", { desc = "Close current tab" })
    vim.keymap.set("n", "<leader>tn", "<cmd>tabn<CR>", { desc = "Go to next tab" })
    vim.keymap.set("n", "<leader>tp", "<cmd>tabp<CR>", { desc = "Go to previous tab" })
    vim.keymap.set("n", "<leader>tf", "<cmd>tabnew %<CR>", { desc = "Open current buffer in new tab" })
end)
```

(Keep the 4-space indent used elsewhere in this file.)

- [ ] **Step 2: Apply and verify both modes**

Run:
```bash
chezmoi apply ~/.config/nvim
TMUX= nvim --headless "+lua print('standalone_to=[' .. vim.fn.maparg(vim.keycode('<Space>to'), 'n') .. ']')" +q 2>&1
TMUX=/tmp/fake,1,0 nvim --headless "+lua print('tmux_to=[' .. vim.fn.maparg(vim.keycode('<Space>to'), 'n') .. ']')" +q 2>&1
```
Expected: first prints `standalone_to=[<Cmd>tabnew<CR>]` (non-empty), second prints `tmux_to=[]` (empty).

- [ ] **Step 3: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_config/nvim/lua/zaid/core/keymaps.lua
git commit -m "refactor(nvim): gate tab keymaps to standalone (tmux windows own workspaces)"
```

---

### Task 3: Gate the floating terminal

**Files:**
- Modify: `dot_config/nvim/lua/zaid/core/commands.lua:39-96`

- [ ] **Step 1: Wrap the floating-terminal block**

In `dot_config/nvim/lua/zaid/core/commands.lua`, replace everything from the `-- Floating terminal` comment (line 39) to the end of the file:

```lua
-- Floating terminal
local state = {
    floating = {
        buf = -1,
        win = -1,
    }
}
local function create_floating_window(opts)
    opts = opts or {}
    local width = opts.width or math.floor(vim.o.columns * 0.8)
    local height = opts.height or math.floor(vim.o.lines * 0.8)

    local col = math.floor((vim.o.columns - width) / 2)
    local row = math.floor((vim.o.lines - height) / 2)

    local buf = nil
    if vim.api.nvim_buf_is_valid(opts.buf) then
        buf = opts.buf
    else
        buf = vim.api.nvim_create_buf(false, true)
    end

    local win_config = {
        relative = "editor",
        border = "rounded",
        style = "minimal",
        width = width,
        height = height,
        col = col,
        row = row,
    }

    local win = vim.api.nvim_open_win(buf, true, win_config)

    return { buf = buf, win = win }
end

local pop_terminal = function()
    if not vim.api.nvim_win_is_valid(state.floating.win) then
        state.floating = create_floating_window { buf = state.floating.buf }
        if vim.bo[state.floating.buf].buftype ~= "terminal" then
            vim.cmd.terminal()
        end

        -- Start float terminal in insert mode
        vim.api.nvim_set_current_win(state.floating.win)
        vim.cmd("startinsert!")

    else
        vim.api.nvim_win_hide(state.floating.win)
    end
end

vim.api.nvim_create_user_command("Terminalpop", pop_terminal, {})
-- Terminal Float State (taught by tj)
vim.keymap.set("t", "<esc><esc>", "<c-\\><c-n>")

vim.keymap.set({ "n", "t" }, "<space>tt", pop_terminal)
```

with the same code wrapped in `when_standalone` (one extra indent level inside the callback; `<esc><esc>` terminal escape stays global since nvim terminals can still open via `:terminal` inside tmux):

```lua
-- Terminal escape works in any :terminal, tmux or not (taught by tj)
vim.keymap.set("t", "<esc><esc>", "<c-\\><c-n>")

-- Floating terminal (standalone only — tmux splits/popups own this inside tmux)
require("zaid.core.env").when_standalone(function()
    local state = {
        floating = {
            buf = -1,
            win = -1,
        }
    }
    local function create_floating_window(opts)
        opts = opts or {}
        local width = opts.width or math.floor(vim.o.columns * 0.8)
        local height = opts.height or math.floor(vim.o.lines * 0.8)

        local col = math.floor((vim.o.columns - width) / 2)
        local row = math.floor((vim.o.lines - height) / 2)

        local buf = nil
        if vim.api.nvim_buf_is_valid(opts.buf) then
            buf = opts.buf
        else
            buf = vim.api.nvim_create_buf(false, true)
        end

        local win_config = {
            relative = "editor",
            border = "rounded",
            style = "minimal",
            width = width,
            height = height,
            col = col,
            row = row,
        }

        local win = vim.api.nvim_open_win(buf, true, win_config)

        return { buf = buf, win = win }
    end

    local pop_terminal = function()
        if not vim.api.nvim_win_is_valid(state.floating.win) then
            state.floating = create_floating_window { buf = state.floating.buf }
            if vim.bo[state.floating.buf].buftype ~= "terminal" then
                vim.cmd.terminal()
            end

            -- Start float terminal in insert mode
            vim.api.nvim_set_current_win(state.floating.win)
            vim.cmd("startinsert!")

        else
            vim.api.nvim_win_hide(state.floating.win)
        end
    end

    vim.api.nvim_create_user_command("Terminalpop", pop_terminal, {})
    vim.keymap.set({ "n", "t" }, "<space>tt", pop_terminal)
end)
```

- [ ] **Step 2: Apply and verify both modes**

Run:
```bash
chezmoi apply ~/.config/nvim
TMUX= nvim --headless "+lua print('standalone_pop=' .. tostring(vim.api.nvim_get_commands({})['Terminalpop'] ~= nil) .. ' tt=[' .. vim.fn.maparg(vim.keycode('<Space>tt'), 'n') .. ']')" +q 2>&1
TMUX=/tmp/fake,1,0 nvim --headless "+lua print('tmux_pop=' .. tostring(vim.api.nvim_get_commands({})['Terminalpop'] ~= nil) .. ' tt=[' .. vim.fn.maparg(vim.keycode('<Space>tt'), 'n') .. ']')" +q 2>&1
```
Expected: first prints `standalone_pop=true tt=[...]` (non-empty map), second prints `tmux_pop=false tt=[]`.

- [ ] **Step 3: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_config/nvim/lua/zaid/core/commands.lua
git commit -m "refactor(nvim): gate floating terminal to standalone (tmux owns terminals)"
```

---

### Task 4: Gate the snacks lazygit keymaps

**Files:**
- Modify: `dot_config/nvim/lua/zaid/plugins/snacks.lua:209-223`

- [ ] **Step 1: Replace the keys list head**

In `dot_config/nvim/lua/zaid/plugins/snacks.lua`, the snacks spec's `keys` table currently begins:

```lua
		-- NOTE: Keymaps
		keys = {
			{
				"<leader>lg",
				function()
					require("snacks").lazygit()
				end,
				desc = "Lazygit",
			},
			{
				"<leader>gl",
				function()
					require("snacks").lazygit.log()
				end,
				desc = "Lazygit Logs",
			},
			{
				"<leader>rN",
```

Replace that opening so the two lazygit entries are produced by the gate helper and the rest of the list is appended unchanged:

```lua
		-- NOTE: Keymaps (lazygit standalone only — prefix+G popup owns it inside tmux)
		keys = vim.list_extend(require("zaid.core.env").standalone_keys({
			{
				"<leader>lg",
				function()
					require("snacks").lazygit()
				end,
				desc = "Lazygit",
			},
			{
				"<leader>gl",
				function()
					require("snacks").lazygit.log()
				end,
				desc = "Lazygit Logs",
			},
		}), {
			{
				"<leader>rN",
```

Then find the closing of the keys table (after the `<leader>hf` help-pages entry):

```lua
			{
				"<leader>hf",
				function()
					require("snacks").picker.help()
				end,
				desc = "Help Pages",
			},
		},
	},
```

and close the `vim.list_extend` call by changing `},\n\t},` to `}),\n\t},`:

```lua
			{
				"<leader>hf",
				function()
					require("snacks").picker.help()
				end,
				desc = "Help Pages",
			},
		}),
	},
```

(Net change: `keys = {` → `keys = vim.list_extend(require("zaid.core.env").standalone_keys({ ...two lazygit entries... }), {` and the matching final `}` → `})`. All other entries are untouched. This file uses tabs for indentation — keep them.)

- [ ] **Step 2: Apply and verify both modes**

lazy.nvim registers `keys` as mappings at startup (they lazy-load the plugin on press), so `maparg` sees them after init:

```bash
chezmoi apply ~/.config/nvim
TMUX= nvim --headless "+lua print('standalone_lg=[' .. vim.fn.maparg(vim.keycode('<Space>lg'), 'n') .. '] pf=[' .. vim.fn.maparg(vim.keycode('<Space>pf'), 'n') .. ']')" +q 2>&1
TMUX=/tmp/fake,1,0 nvim --headless "+lua print('tmux_lg=[' .. vim.fn.maparg(vim.keycode('<Space>lg'), 'n') .. '] pf=[' .. vim.fn.maparg(vim.keycode('<Space>pf'), 'n') .. ']')" +q 2>&1
```
Expected: first prints non-empty `standalone_lg=[...]` and non-empty `pf=[...]`; second prints empty `tmux_lg=[]` but **still non-empty** `pf=[...]` (proves only lazygit keys were gated, pickers intact).

- [ ] **Step 3: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_config/nvim/lua/zaid/plugins/snacks.lua
git commit -m "refactor(nvim): gate snacks lazygit keys to standalone"
```

---

### Task 5: Add tmux `prefix+G` lazygit popup

**Files:**
- Modify: `dot_tmux/conf.d/keys.conf` (after the Television bindings, line 71)

- [ ] **Step 1: Add the binding**

In `dot_tmux/conf.d/keys.conf`, after:

```tmux
# Television: windows needing attention (bells from Claude, activity)
bind-key "a" display-popup -E -w 80% -h 70% -T ' Alerts ' 'tv tmux-alerts'
```

insert:

```tmux
# Lazygit popup in current pane's directory (G — lowercase g is tmux-jump)
bind-key "G" display-popup -E -w 90% -h 90% -d '#{pane_current_path}' -T ' Lazygit ' 'lazygit'
```

- [ ] **Step 2: Apply and validate the config parses**

Run:
```bash
chezmoi apply ~/.tmux
tmux start-server \; source-file ~/.tmux/conf.d/keys.conf 2>&1 && tmux list-keys | grep -F 'lazygit'
```
Expected: no parse errors; `list-keys` shows a line binding `G` to `display-popup ... lazygit`.

- [ ] **Step 3: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_tmux/conf.d/keys.conf
git commit -m "feat(tmux): bind prefix+G to lazygit popup in current path"
```

---

### Task 6: Stop "INSERT" showing twice

lualine's `mode` component already shows the mode; vim's native `showmode` prints a second `-- INSERT --` on the command line below it.

**Files:**
- Modify: `dot_config/nvim/lua/zaid/core/options.lua:16`

- [ ] **Step 1: Disable native showmode**

In `dot_config/nvim/lua/zaid/core/options.lua`, replace:

```lua
vim.opt.laststatus = 3
```

with:

```lua
vim.opt.laststatus = 3
vim.opt.showmode = false -- lualine already shows the mode
```

- [ ] **Step 2: Apply and verify**

Run:
```bash
chezmoi apply ~/.config/nvim
nvim --headless "+lua print('showmode=' .. tostring(vim.o.showmode))" +q 2>&1
```
Expected: prints `showmode=false`.

- [ ] **Step 3: Commit**

```bash
cd ~/.local/share/chezmoi
git add dot_config/nvim/lua/zaid/core/options.lua
git commit -m "fix(nvim): disable native showmode (lualine shows mode)"
```

---

### Task 7: Archive incline (filename already in lualine)

incline.nvim floats a per-window title at the top right, which covers content in small tmux panes. lualine's `lualine_c` filename component (`path = 3`, absolute path) already shows the name in the status bar, so incline is removed by archiving — per repo convention, archived plugin specs move to `plugins_archive/` (not loaded by lazy.nvim, which only imports `zaid.plugins`) and nothing is deleted.

**Files:**
- Move: `dot_config/nvim/lua/zaid/plugins/incline.lua` → `dot_config/nvim/lua/zaid/plugins_archive/incline.lua`

- [ ] **Step 1: Move the spec to the archive**

```bash
cd ~/.local/share/chezmoi
git mv dot_config/nvim/lua/zaid/plugins/incline.lua dot_config/nvim/lua/zaid/plugins_archive/incline.lua
```

- [ ] **Step 2: Apply and verify incline no longer loads**

Run:
```bash
chezmoi apply ~/.config/nvim
nvim --headless "+lua local p = require('lazy.core.config').plugins; print('incline_spec=' .. tostring(p['incline.nvim'] ~= nil))" +q 2>&1
```
Expected: prints `incline_spec=false`. Also confirm visually later that the filename still appears in the lualine status bar.

- [ ] **Step 3: Commit**

```bash
cd ~/.local/share/chezmoi
git commit -m "refactor(nvim): archive incline, lualine statusbar already shows filename"
```

---

### Task 8: End-to-end verification

**Files:** none (verification only)

- [ ] **Step 1: Full startup health check in both modes**

Run:
```bash
TMUX= nvim --headless "+lua vim.print('standalone boot ok')" +q 2>&1
TMUX=/tmp/fake,1,0 nvim --headless "+lua vim.print('tmux boot ok')" +q 2>&1
```
Expected: each prints its message with no Lua errors above it.

- [ ] **Step 2: Manual smoke test (real tmux)**

Inside a real tmux session: open `nvim`, confirm `<Space>tt`, `<Space>lg`, `<Space>to` do nothing; press `prefix+r` to reload tmux config, then `prefix+G` and confirm lazygit pops up in the current path. Outside tmux (bare Ghostty): open `nvim`, confirm all three work.

- [ ] **Step 3: Spec status + final state**

Run:
```bash
cd ~/.local/share/chezmoi
git status --short
git log --oneline -8
```
Expected: clean tree; the seven commits from Tasks 1–7 present.
