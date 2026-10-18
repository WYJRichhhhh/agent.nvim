local M = {}

function M.highlights()
    local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
    local float = vim.api.nvim_get_hl(0, { name = "NormalFloat", link = false })
    local light = vim.o.background == "light"
    -- 透明主题没有显式底色；Agent 终端单独使用实色，避免透出终端的黑色背景。
    vim.api.nvim_set_hl(0, "AgentNormal", {
        fg = float.fg or normal.fg or (light and "#16181a" or "#ffffff"),
        bg = float.bg or normal.bg or (light and "#ffffff" or "#16181a"),
    })
    vim.api.nvim_set_hl(0, "AgentBorder", { link = "FloatBorder" })
    vim.api.nvim_set_hl(0, "AgentTitle", { link = "FloatTitle" })
end

function M.find(session)
    if not session or not vim.api.nvim_buf_is_valid(session.bufnr) then
        return
    end
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == session.bufnr then
            return win
        end
    end
end

local function label(session)
    local review = require("agent.review").status()
    local suffix = review.enabled
            and ((review.follow and " · 跟随" or " · 暂停") .. " · " .. review.files .. " 文件")
        or ""
    return session.backend .. suffix
end

function M.refresh(session)
    local win = M.find(session)
    if not win then
        return
    end
    if vim.api.nvim_win_get_config(win).relative == "" then
        vim.wo[win].winbar = "Agent: " .. label(session)
    else
        vim.api.nvim_win_set_config(
            win,
            { title = (" %s · %s "):format(label(session), session.cwd):gsub("[%c]", " "), title_pos = "center" }
        )
    end
end

local function size(value, total)
    return math.max(1, math.min(total, math.floor(value <= 1 and total * value or value)))
end

local function float_config(session)
    local opts = require("agent.config").options.window
    local columns = math.max(1, vim.o.columns - 4)
    local lines = math.max(1, vim.o.lines - vim.o.cmdheight - 4)
    local width, height = size(opts.width, columns), size(opts.height, lines)
    return {
        relative = "editor",
        style = "minimal",
        border = opts.border,
        width = width,
        height = height,
        col = math.max(0, math.floor((vim.o.columns - width) / 2) - 1),
        row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
        title = (" %s · %s "):format(label(session), session.cwd):gsub("[%c]", " "),
        title_pos = "center",
    }
end

function M.show(session)
    local win = M.find(session)
    if vim.api.nvim_get_current_buf() ~= session.bufnr then
        session.return_win = vim.api.nvim_get_current_win()
        session.return_buf = vim.api.nvim_get_current_buf()
    end
    if win then
        vim.api.nvim_set_current_win(win)
    else
        local opts = require("agent.config").options.window
        if opts.layout == "float" then
            win = vim.api.nvim_open_win(session.bufnr, true, float_config(session))
        else
            local vertical = opts.layout == "right"
            local amount = size(vertical and opts.width or opts.height, vertical and vim.o.columns or vim.o.lines)
            vim.cmd(("botright %d%s"):format(amount, vertical and "vsplit" or "split"))
            win = vim.api.nvim_get_current_win()
            vim.api.nvim_win_set_buf(win, session.bufnr)
            vim.wo[win].winbar = ("Agent: %s"):format(label(session))
        end
        vim.wo[win].number = false
        vim.wo[win].relativenumber = false
        vim.wo[win].signcolumn = "no"
    end
    M.highlights()
    vim.wo[win].winblend = 0
    vim.wo[win].winhighlight = require("agent.config").options.window.winhighlight
    session.win_id = win
    if session.state == "running" and require("agent.config").options.terminal.start_insert then
        vim.cmd.startinsert()
    end
    return win
end

function M.hide(session)
    if not session then
        return
    end
    local wins = vim.fn.win_findbuf(session.bufnr)
    vim.cmd.stopinsert()
    for _, win in ipairs(wins) do
        if vim.api.nvim_win_is_valid(win) then
            -- 用户可能用 :only 将终端留作唯一窗口；此时换 buffer 而非退出编辑器。
            if #vim.api.nvim_list_wins() == 1 then
                local buf = session.return_buf
                if not buf or not vim.api.nvim_buf_is_valid(buf) or buf == session.bufnr then
                    buf = vim.api.nvim_create_buf(true, false)
                end
                vim.api.nvim_win_set_buf(win, buf)
            else
                vim.api.nvim_win_close(win, true)
            end
        end
    end
    if session.return_win and vim.api.nvim_win_is_valid(session.return_win) then
        vim.api.nvim_set_current_win(session.return_win)
    end
    session.win_id = nil
end

function M.resize(session)
    local win = M.find(session)
    if win and vim.api.nvim_win_get_config(win).relative ~= "" then
        vim.api.nvim_win_set_config(win, float_config(session))
    end
end

return M
