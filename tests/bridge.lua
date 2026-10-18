vim.o.columns = 180
vim.o.lines = 50
local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
local a = require("agent")
local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")
temp = vim.uv.fs_realpath(temp)
vim.fn.writefile({ "before" }, temp .. "/sample.txt")
local node = vim.fn.exepath("node")
assert(node ~= "")
local function wait(fn, message)
    assert(vim.wait(12000, fn, 25), message)
end
local function text()
    local s = a.status()
    return s.bufnr and table.concat(vim.api.nvim_buf_get_lines(s.bufnr, 0, -1, false), "\n") or ""
end
local function send(value)
    vim.fn.chansend(a.status().job_id, value .. "\n")
end
local ok, err = xpcall(function()
    a.setup({
        backend = "codex",
        cwd = temp,
        codex = { enabled = true, node = node, startup_timeout = 5000 },
        window = { layout = "right", width = 0.4 },
        terminal = { start_insert = false, show_hint = false },
        backends = {
            codex = {
                command = { root .. "/tests/fixtures/fake_codex.py" },
                env = { AGENT_TEST_NODE = node, AGENT_TEST_PID_FILE = temp .. "/server.pid" },
            },
        },
    })
    a.open()
    wait(function()
        return text():find("READY_NATIVE_TUI", 1, true)
    end, "native terminal did not start")
    local job = a.status().job_id
    send("edit")
    wait(function()
        return a.status().bridge.state == "connected"
    end, "observer did not subscribe")
    assert(a.status().review.files == 0, "approval should not be answered by observer")
    send("approve")
    wait(function()
        return a.status().review.files == 1
    end, "fileChange was not rendered")
    assert(vim.fn.readfile(temp .. "/sample.txt")[1] == "after")
    local sourcebuf = vim.fn.bufnr(temp .. "/sample.txt")
    assert(sourcebuf > 0)
    assert(#vim.api.nvim_buf_get_extmarks(sourcebuf, vim.api.nvim_create_namespace("AgentReview"), 0, -1, {}) == 2)
    assert(vim.api.nvim_get_current_buf() == a.status().bufnr, "review stole terminal focus")
    a.diff()
    assert(vim.bo.filetype == "diff")
    assert(not vim.bo.modifiable)
    a.focus()
    send("stats")
    wait(function()
        return text():find("wrongAnswers", 1, true)
    end, "no statistics")
    assert(text():find('"wrongAnswers": 0', 1, true) or text():find('"wrongAnswers":0', 1, true))
    a.hide()
    a.open()
    assert(a.status().job_id == job, "toggle restarted CLI")
    local pid = tonumber(vim.fn.readfile(temp .. "/server.pid")[1])
    a.stop()
    wait(function()
        return not vim.uv.kill(pid, 0)
    end, "App Server leaked after stop")
    assert(not require("agent.review").status().enabled)
    -- Stopping during async startup must prevent a late terminal or server.
    vim.fn.delete(temp .. "/server.pid")
    a.open()
    local starting = a.status().bufnr
    a.open()
    assert(a.status().bufnr == starting)
    a.stop()
    vim.wait(500, function()
        return false
    end, 25)
    assert(a.status().state == "idle")
    if vim.fn.filereadable(temp .. "/server.pid") == 1 then
        local early_pid = tonumber(vim.fn.readfile(temp .. "/server.pid")[1])
        wait(function()
            return not vim.uv.kill(early_pid, 0)
        end, "startup cancellation leaked server")
    end
    -- Native CLI exit shuts down the server while keeping received review data inspectable.
    a.open()
    wait(function()
        return text():find("READY_NATIVE_TUI", 1, true)
    end, "second CLI did not start")
    local exit_pid = tonumber(vim.fn.readfile(temp .. "/server.pid")[1])
    send("quit")
    wait(function()
        return a.status().state == "exited"
    end, "native CLI did not exit")
    wait(function()
        return not vim.uv.kill(exit_pid, 0)
    end, "native exit leaked server")
    assert(a.status().review.enabled)
    a.stop()
    print(
        "AGENT_BRIDGE_OK token-auth / retry / native approval / real file / review / singleton / cancellation / native exit / wrapper process cleanup"
    )
end, debug.traceback)
a.stop()
vim.fn.delete(temp, "rf")
if not ok then
    io.stderr:write(err .. "\n")
    vim.cmd.cquit(1)
end
vim.cmd("qa!")
