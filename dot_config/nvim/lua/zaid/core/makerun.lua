-- Pick a Makefile target (found by walking up from the current file) and run it
-- as a live terminal in a floating window. Promote the float into a split to keep
-- the running process and its scrollback while you work.
local M = {}
local state = { win = nil, buf = nil }

-- Walk up from the current file's dir until we hit a Makefile
local function find_makefile()
    local dir = vim.fn.expand("%:p:h")
    if dir == "" then dir = vim.fn.getcwd() end
    local found = vim.fs.find("Makefile", { upward = true, path = dir, type = "file" })
    return found[1]
end

-- Pull target names out of the Makefile (lines like `build:` / `test:`)
local function parse_targets(makefile)
    local targets = {}
    for line in io.lines(makefile) do
        local t = line:match("^([%a][%w_%-]*)%s*:")
        if t and t ~= ".PHONY" then
            targets[#targets + 1] = t
        end
    end
    return targets
end

-- Centered floating window holding `buf`
local function open_float(buf)
    local width  = math.floor(vim.o.columns * 0.8)
    local height = math.floor(vim.o.lines * 0.8)
    return vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = math.floor((vim.o.lines - height) / 2),
        col = math.floor((vim.o.columns - width) / 2),
        style = "minimal",
        border = "rounded",
    })
end

-- <leader>qr
function M.run()
    local makefile = find_makefile()
    if not makefile then
        return vim.notify("No Makefile found upward from current file", vim.log.levels.WARN)
    end
    local root    = vim.fn.fnamemodify(makefile, ":h")
    local targets = parse_targets(makefile)
    if #targets == 0 then
        return vim.notify("No targets in " .. makefile, vim.log.levels.WARN)
    end

    vim.ui.select(targets, { prompt = "make target (" .. root .. "):" }, function(choice)
        if not choice then return end
        local buf = vim.api.nvim_create_buf(false, true)
        state.buf = buf
        state.win = open_float(buf) -- enters the float, so buf is current
        vim.fn.jobstart({ "make", choice }, { term = true, cwd = root })
        -- Stay in Normal-mode (mode "nt") so the buffer is navigable and <leader>
        -- mappings fire. Do NOT startinsert: in Terminal-mode, once the job exits
        -- the next keystroke closes the terminal (and leaks through). Press `i` to
        -- interact with a live process; `<esc>` brings you back to navigate.
        vim.keymap.set("t", "<esc>", [[<C-\><C-n>]], { buffer = buf })
        vim.keymap.set("n", "q", M.close, { buffer = buf, desc = "Close run float" })
        vim.keymap.set("n", "g?", M.cheatsheet, { buffer = buf, desc = "Show run buffer keys" })
    end)
end

-- Buffer-local keys available inside a run buffer (single source of truth for g?)
M.keys = {
    { "q",        "Close this float (job keeps running, hidden)" },
    { "<space>o", "Promote float into a bottom split" },
    { "i",        "Enter Terminal-mode to type into a live process" },
    { "<esc>",    "Leave Terminal-mode, back to navigating" },
    { "G",        "Jump to the bottom (follow output)" },
    { "g?",       "Show this list" },
}

-- g? — show the available keys
function M.cheatsheet()
    local lines = { "makerun keys:" }
    for _, k in ipairs(M.keys) do
        lines[#lines + 1] = string.format("  %-9s %s", k[1], k[2])
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "makerun" })
end

-- q — close the floating run window (the terminal buffer/job stays alive, hidden)
function M.close()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_win_close(state.win, false)
        state.win = nil
    else
        vim.cmd("close")
    end
end

-- <leader>o — promote the float into a real split, same buffer, process intact
function M.promote()
    if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
        return vim.notify("No floating run buffer to promote", vim.log.levels.INFO)
    end
    vim.api.nvim_win_close(state.win, false)
    state.win = nil
    vim.cmd("botright split")
    vim.api.nvim_win_set_buf(0, state.buf)
end

return M
