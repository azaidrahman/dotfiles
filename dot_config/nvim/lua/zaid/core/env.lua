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
