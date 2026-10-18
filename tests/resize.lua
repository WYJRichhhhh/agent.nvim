assert(#vim.api.nvim_list_uis() > 0, "Run python3 tests/ui_resize.py for an attached UI")
vim.o.columns = 160
vim.o.lines = 45
local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
local agent = require("agent")
local command = { vim.fn.exepath("python3"), "-u", root .. "/tests/fixtures/fake_cli.py" }
local function wait(fn, msg)
    assert(vim.wait(3000, fn, 20), msg)
end
local function text(buf)
    return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end
local checks = 0
local ok, err = xpcall(function()
    for _, layout in ipairs({ "float", "right", "bottom" }) do
        agent.setup({
            backend = "fake",
            window = { layout = layout, width = 0.42, height = 0.4 },
            terminal = { start_insert = false, show_hint = false },
            backends = { fake = { command = command } },
        })
        agent.open()
        local session = agent.status()
        local win = vim.api.nvim_get_current_win()
        local pid = vim.fn.jobpid(session.job_id)
        wait(function()
            return text(session.bufnr):find("READY", 1, true)
        end, "fixture not ready")
        vim.fn.chansend(session.job_id, "pending")
        for _, dims in ipairs({ { 240, 65 }, { 100, 32 }, { 190, 52 } }) do
            vim.o.columns = dims[1]
            vim.o.lines = dims[2]
            -- Multiple events simulate zoom/unzoom and SIGWINCH bursts.
            vim.api.nvim_exec_autocmds("VimResized", {})
            vim.api.nvim_exec_autocmds("VimResized", {})
            wait(function()
                if layout == "right" then
                    return vim.api.nvim_win_get_width(win) == math.floor(dims[1] * 0.42)
                end
                if layout == "bottom" then
                    return vim.api.nvim_win_get_height(win) == math.floor(dims[2] * 0.4)
                end
                local cfg = vim.api.nvim_win_get_config(win)
                return cfg.width == math.floor((dims[1] - 4) * 0.42)
                    and cfg.col == math.max(0, math.floor((dims[1] - cfg.width) / 2) - 1)
            end, layout .. " did not adapt after resize")
            assert(vim.api.nvim_get_current_win() == win, "resize stole focus")
            assert(
                agent.status().job_id == session.job_id and vim.fn.jobpid(session.job_id) == pid,
                "resize restarted CLI"
            )
        end
        vim.fn.chansend(session.job_id, "-continued\nSIZE\n")
        wait(function()
            return text(session.bufnr):find("REPLY:pending-continued", 1, true)
        end, "resize lost unfinished input")
        local size = "SIZE:" .. vim.api.nvim_win_get_width(win) .. "x" .. vim.api.nvim_win_get_height(win)
        wait(function()
            return text(session.bufnr):find(size, 1, true)
        end, "PTY dimensions differ from window: " .. size)
        -- A delayed resize must not reopen an already hidden session.
        vim.api.nvim_exec_autocmds("VimResized", {})
        agent.hide()
        vim.wait(80, function()
            return false
        end, 10)
        assert(not agent.status().visible)
        agent.open()
        assert(agent.status().job_id == session.job_id)
        if layout ~= "float" then
            vim.cmd.only()
            vim.api.nvim_exec_autocmds("VimResized", {})
            vim.wait(80, function()
                return false
            end, 10)
            assert(#vim.api.nvim_tabpage_list_wins(0) == 1)
        end
        agent.stop()
        checks = checks + 1
        print("PASS " .. layout .. " resize / PTY / focus / input / hide / singleton")
    end
    -- A queued callback from a previous session must not resize a replacement session.
    agent.setup({
        backend = "fake",
        terminal = { start_insert = false, show_hint = false },
        backends = {
            fake = { command = command },
        },
    })
    agent.open()
    vim.api.nvim_exec_autocmds("VimResized", {})
    agent.stop()
    agent.open()
    local next_job = agent.status().job_id
    vim.wait(80, function()
        return false
    end, 10)
    assert(agent.status().job_id == next_job)
    print("AGENT_RESIZE_OK " .. checks .. " layouts + stale callback isolation")
end, debug.traceback)
agent.stop()
if not ok then
    io.stderr:write(err .. "\n")
    vim.cmd.cquit(1)
end
vim.cmd("qa!")
