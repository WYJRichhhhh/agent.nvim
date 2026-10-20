vim.opt.rtp:prepend(vim.fn.getcwd())
vim.o.columns = 160
vim.o.lines = 45
local a = require("agent")
local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")
temp = vim.uv.fs_realpath(temp)
vim.fn.writefile({ "before" }, temp .. "/sample.txt")
local function text()
    return table.concat(vim.api.nvim_buf_get_lines(a.status().bufnr, 0, -1, false), "\n")
end
local ok, err = xpcall(function()
    for _, backend in ipairs({ "codex", "claude" }) do
        a.setup({
            backend = backend,
            cwd = temp,
            codex = { enabled = true },
            claude = { enabled = true },
            terminal = { start_insert = false, show_hint = false },
            window = { layout = "right" },
            backends = {
                codex = {
                    command = { vim.fn.getcwd() .. "/tests/fixtures/fake_codex.py" },
                    env = { AGENT_TEST_NODE = vim.fn.exepath("node"), AGENT_TEST_REQUIRE_POLICY = "1" },
                },
                claude = {
                    command = {
                        vim.fn.getcwd() .. "/tests/fixtures/fake_claude.py",
                        "--settings",
                        '{"env":{"AGENT_KEEP_SETTING":"kept"}}',
                    },
                    env = { AGENT_TEST_INHERITED = "unchanged" },
                },
            },
        })
        a.open()
        assert(vim.wait(8000, function()
            return text():find("READY", 1, true)
        end))
        local job, terminal = a.status().job_id, a.status().bufnr
        vim.fn.chansend(job, "show\n")
        assert(
            vim.wait(10000, function()
                return text():find("SHOW_RESULT:", 1, true)
            end),
            text()
        )
        assert(a.status().code.active and a.status().code.locations == 1, text())
        assert(vim.api.nvim_get_current_buf() == terminal)
        assert(not a.status().review.follow)
        local source = vim.fn.bufnr(temp .. "/sample.txt")
        assert(
            #vim.api.nvim_buf_get_extmarks(source, vim.api.nvim_create_namespace("AgentCodeExplanation"), 0, -1, {})
                == 2
        )
        a.hide()
        a.open()
        assert(a.status().job_id == job and a.status().code.active)
        a.clear()
        assert(
            #vim.api.nvim_buf_get_extmarks(source, vim.api.nvim_create_namespace("AgentCodeExplanation"), 0, -1, {})
                == 0
        )
        a.stop()
    end
    print(
        "AGENT_EDITOR_BRIDGE_OK Codex + Claude / stdio MCP → bridge → actual source + highlight → acknowledged result / focus / toggle / clear"
    )
end, debug.traceback)
a.stop()
vim.fn.delete(temp, "rf")
if not ok then
    io.stderr:write(err .. "\n")
    vim.cmd.cquit(1)
end
vim.cmd("qa!")
