local M = {}
local previous
function M.release()
    if previous ~= nil then
        -- Preserve a user's explicit change made while the Agent was focused.
        if vim.o.mouse == "a" then
            vim.o.mouse = previous
        end
        previous = nil
    end
end
function M.update(session)
    local capture = require("agent.config").options.terminal.capture_mouse
    local focused = session
        and vim.api.nvim_buf_is_valid(session.bufnr)
        and vim.api.nvim_get_current_buf() == session.bufnr
    if not capture or not focused then
        M.release()
        return
    end
    if previous == nil then
        previous = vim.o.mouse
        vim.o.mouse = "a"
    end
end
return M
