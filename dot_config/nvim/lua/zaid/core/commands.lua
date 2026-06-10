vim.api.nvim_create_autocmd("TextYankPost", {
	desc = "Highlight when yanking (copying) text",
	group = vim.api.nvim_create_augroup("kickstart-highlight-yank", { clear = true }),
	callback = function()
		vim.hl.on_yank()
		if vim.v.event.operator ~= "y" then
			return
		end
		local lines = vim.v.event.regcontents or {}
		local line_count = #lines
		local char_count = 0
		for _, l in ipairs(lines) do
			char_count = char_count + #l
		end
		local msg = line_count == 1
			and string.format("%d chars", char_count)
			or string.format("%d lines, %d chars", line_count, char_count)
		vim.notify(msg, vim.log.levels.INFO, { title = "Yanked" })
	end,
})

vim.api.nvim_create_autocmd("QuickFixCmdPost", {
	callback = function()
		vim.cmd([[Trouble qflist open]])
	end,
})

-- Restore cursor position when reopening a file
vim.api.nvim_create_autocmd("BufReadPost", {
	callback = function(args)
		local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
		local line_count = vim.api.nvim_buf_line_count(args.buf)
		if mark[1] > 0 and mark[1] <= line_count then
			pcall(vim.api.nvim_win_set_cursor, 0, mark)
		end
	end,
})

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
