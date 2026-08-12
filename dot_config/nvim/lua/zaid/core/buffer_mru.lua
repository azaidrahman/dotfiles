-- Track buffer visit order so Shift-H/L move by recency instead of
-- :bnext/:bprevious's fixed buffer-number order.
local M = {}
local mru = {} -- bufnrs, most recently entered first

local function drop_stale()
    local valid = {}
    for _, buf in ipairs(mru) do
        if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted then
            valid[#valid + 1] = buf
        end
    end
    mru = valid
end

function M.record(buf)
    if not vim.bo[buf].buflisted then return end
    for i, b in ipairs(mru) do
        if b == buf then
            table.remove(mru, i)
            break
        end
    end
    table.insert(mru, 1, buf)
end

-- Shift-H: jump to the buffer entered just before this one
function M.jump_recent()
    drop_stale()
    if mru[2] then
        vim.api.nvim_set_current_buf(mru[2])
    end
end

-- Shift-L: jump to the least-recently-entered buffer still open
function M.jump_oldest()
    drop_stale()
    if mru[#mru] and mru[#mru] ~= mru[1] then
        vim.api.nvim_set_current_buf(mru[#mru])
    end
end

vim.api.nvim_create_autocmd("BufEnter", {
    group = vim.api.nvim_create_augroup("zaid-buffer-mru", { clear = true }),
    callback = function(args) M.record(args.buf) end,
})

return M
