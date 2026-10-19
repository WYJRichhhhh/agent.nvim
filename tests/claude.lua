vim.o.columns = 180
vim.o.lines = 50
vim.opt.rtp:prepend(vim.fn.getcwd())
local root = vim.fn.getcwd()
local a = require("agent")
local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")
temp = vim.uv.fs_realpath(temp)
vim.fn.writefile({ "before" }, temp .. "/sample.txt")
local function text()
    local s = a.status()
    return s.bufnr and table.concat(vim.api.nvim_buf_get_lines(s.bufnr, 0, -1, false), "\n") or ""
end
local function wait(fn, message)
    assert(vim.wait(12000, fn, 20), message)
end
local function send(value)
    vim.fn.chansend(a.status().job_id, value .. "\n")
    wait(function()
        return text():find("DONE:" .. value, 1, true)
    end, value .. " did not finish")
end
local ok, err = xpcall(function()
    a.setup({
        backend = "claude",
        cwd = temp,
        claude = { enabled = true },
        window = { layout = "right" },
        terminal = { start_insert = false, show_hint = false },
        backends = {
            claude = {
                command = {
                    root .. "/tests/fixtures/fake_claude.py",
                    "--settings",
                    '{"env":{"AGENT_KEEP_SETTING":"kept"}}',
                },
                env = { AGENT_TEST_INHERITED = "unchanged" },
            },
        },
    })
    a.open()
    wait(function()
        return text():find("READY_CLAUDE_TUI", 1, true)
    end, "Claude hook session not started")
    assert(a.status().bridge.state == "connected")
    assert(a.status().bridge.thread_id == "fixture-claude")
    local job, buf = a.status().job_id, a.status().bufnr
    send("begin")
    send("edit")
    wait(function()
        return a.status().review.files == 1
    end, "non-Git edit missing")
    local source = vim.fn.bufnr(temp .. "/sample.txt")
    assert(source > 0 and vim.api.nvim_get_current_buf() == buf)
    assert(#vim.api.nvim_buf_get_extmarks(source, vim.api.nvim_create_namespace("AgentReview"), 0, -1, {}) == 2)
    send("edit-again")
    assert(vim.api.nvim_buf_get_lines(source, 0, 1, false)[1] == "after twice")
    a.filediff()
    local diff = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    assert(diff:find("-before", 1, true) and diff:find("+after twice", 1, true), diff)
    a.focus()
    a.hide()
    a.open()
    assert(a.status().job_id == job and a.status().bufnr == buf)
    send("failed")
    assert(a.status().review.files == 1)
    send("revert")
    wait(function()
        return a.status().review.files == 0
    end, "reverted edit not removed")
    -- New prompts reset the baseline; edits remain available after a natural CLI exit.
    send("begin")
    send("edit")
    local pid = vim.fn.jobpid(job)
    vim.fn.chansend(job, "quit\n")
    wait(function()
        return a.status().state == "exited"
    end, "natural exit not handled")
    assert(a.status().review.files == 1)
    assert(not vim.uv.kill(pid, 0))
    a.stop()
    assert(a.status().state == "idle")
    -- Review disabled preserves the original command unmodified.
    a.setup({ claude = { enabled = false }, backends = { claude = { command = { "cat" } } } })
    a.open("claude")
    assert(not a.status().bridge)
    a.stop()
    print(
        "AGENT_CLAUDE_OK real command hooks / non-Git writes / cumulative diff / reverts / failed tools / settings and env / singleton / exit / terminal-only"
    )
end, debug.traceback)
a.stop()
vim.fn.delete(temp, "rf")
if not ok then
    io.stderr:write(err .. "\n")
    vim.cmd.cquit(1)
end
vim.cmd("qa!")
