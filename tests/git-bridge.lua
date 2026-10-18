vim.o.columns = 180
vim.o.lines = 50
local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
local agent = require("agent")
local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")
temp = vim.uv.fs_realpath(temp)
local function git(args)
    local cmd = { "git", "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false", "-C", temp }
    vim.list_extend(cmd, args)
    local r = vim.system(cmd, { text = true }):wait()
    assert(r.code == 0, r.stderr)
end
local function wait(fn, msg)
    assert(vim.wait(15000, fn, 25), msg)
end
local function text()
    local s = agent.status()
    return s.bufnr and table.concat(vim.api.nvim_buf_get_lines(s.bufnr, 0, -1, false), "\n") or ""
end
local function send(value)
    vim.fn.chansend(agent.status().job_id, value .. "\n")
end
local ok, err = xpcall(function()
    git({ "init", "-q" })
    vim.fn.writefile({ "committed version" }, temp .. "/doc.md")
    vim.fn.writefile({ ".worktrees/" }, temp .. "/.gitignore")
    git({ "add", "." })
    git({ "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "base" })
    vim.fn.writefile({ "user change before turn" }, temp .. "/doc.md")
    agent.setup({
        backend = "codex",
        cwd = temp,
        codex = { enabled = true },
        review = { follow = false },
        window = { layout = "right", width = 0.42 },
        terminal = { start_insert = false, show_hint = false },
        backends = {
            codex = {
                command = { root .. "/tests/fixtures/fake_codex.py" },
                env = {
                    AGENT_TEST_NODE = vim.fn.exepath("node"),
                },
            },
        },
    })
    agent.open()
    wait(function()
        return text():find("READY_NATIVE_TUI", 1, true)
    end, "TUI startup failed")
    send("edit")
    wait(function()
        return agent.status().bridge.state == "connected"
    end, "observer not connected")
    vim.wait(300, function()
        return false
    end, 25)
    send("script")
    wait(function()
        return agent.status().review.files == 1
    end, "script write not detected")
    assert(not agent.status().review.follow, "Git events must not resume following")
    agent.diff()
    local diff = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    assert(diff:find("-user change before turn", 1, true))
    assert(diff:find("+changed by script", 1, true))
    agent.focus()
    send("worktree-script")
    wait(function()
        return agent.status().review.files == 2
    end, "new worktree script write not detected")
    -- Explicit Git workspace inspection can show the already completed worktree changes.
    local original = vim.ui.select
    vim.ui.select = function(roots, _, callback)
        local wanted = temp .. "/.worktrees/docs"
        assert(vim.tbl_contains(roots, wanted))
        callback(wanted)
    end
    agent.gitdiff()
    wait(function()
        return vim.bo.filetype == "diff"
            and table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("+worktree script update", 1, true)
    end, "worktree Git diff did not open")
    vim.ui.select = original
    vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(0) - 1, 0 })
    vim.api.nvim_feedkeys("gf", "x", false)
    assert(vim.api.nvim_buf_get_name(0) == temp .. "/.worktrees/docs/doc.md", "gf did not open worktree source")
    print(
        "AGENT_GIT_BRIDGE_OK shell writes / paused collection / pre-existing edits / new worktree / explicit Git diff"
    )
end, debug.traceback)
agent.stop()
vim.wait(1400, function()
    return false
end, 50)
vim.fn.delete(temp, "rf")
if not ok then
    io.stderr:write(err .. "\n")
    vim.cmd.cquit(1)
end
vim.cmd("qa!")
