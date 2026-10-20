vim.opt.rtp:prepend(vim.fn.getcwd())
local review, explain = require("agent.review"), require("agent.explain")
local config = require("agent.config")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = vim.uv.fs_realpath(root)
local path = root .. "/source.lua"
local other = root .. "/other.lua"
vim.fn.writefile({ "local function core()", "    return 42", "end", "return core()" }, path)
vim.fn.writefile({ "return 'other'" }, other)
local editor = vim.api.nvim_get_current_win()
local terminal = vim.api.nvim_create_buf(false, true)
vim.bo[terminal].buftype = "nofile"
local agentwin =
    vim.api.nvim_open_win(terminal, true, { relative = "editor", row = 0, col = 0, width = 30, height = 5 })
local session = { backend = "codex", cwd = root, return_win = editor, bufnr = terminal }
review.attach(session, config.options.review)
explain.attach(session, config.options.code)
local args = {
    title = "核心代码",
    locations = {
        {
            file = "source.lua",
            ranges = {
                {
                    start = 1,
                    ["end"] = 3,
                    label = "核心实现",
                    expected_text = "local function core()\n    return 42\nend",
                },
            },
        },
        { file = "other.lua", ranges = { { start = 1, label = "辅助文件" } } },
    },
}
local function marks(buf)
    return vim.api.nvim_buf_get_extmarks(buf, vim.api.nvim_create_namespace("AgentCodeExplanation"), 0, -1, {})
end
local ok, err = xpcall(function()
    local result = explain.show(args)
    assert(result.ok and result.locations == 2, vim.inspect(result))
    local source = vim.api.nvim_win_get_buf(editor)
    assert(vim.api.nvim_buf_get_name(source) == path and #marks(source) == 4)
    assert(vim.api.nvim_get_current_win() == agentwin)
    assert(not review.status().follow)
    assert(vim.fn.bufnr(other) == -1 or not vim.api.nvim_buf_is_loaded(vim.fn.bufnr(other)), "loaded every location")
    local bad = vim.deepcopy(args)
    bad.locations[2].ranges[1].start = 900
    assert(not explain.show(bad).ok and #marks(source) == 4, "invalid batch changed the view")
    bad = vim.deepcopy(args)
    bad.locations[1].ranges[1].expected_text = "stale"
    assert(not explain.show(bad).ok)
    bad = vim.deepcopy(args)
    bad.locations[1].file = "/etc/hosts"
    assert(not explain.show(bad).ok)
    vim.api.nvim_buf_set_lines(source, 1, 2, false, { "unsaved" })
    assert(not explain.show(args).ok)
    assert(vim.api.nvim_buf_get_lines(source, 1, 2, false)[1] == "unsaved")
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = source })
    assert(#marks(source) == 0)
    vim.api.nvim_buf_set_lines(source, 1, 2, false, { "    return 42" })
    vim.bo[source].modified = false
    assert(explain.show(args).ok)
    local original = vim.ui.select
    local late
    vim.ui.select = function(entries, _, callback)
        late = callback
        callback(entries[2], 2)
    end
    explain.locations()
    vim.ui.select = original
    assert(vim.api.nvim_get_current_win() == editor and vim.api.nvim_buf_get_name(0) == other)
    assert(#marks(vim.api.nvim_get_current_buf()) == 2)
    assert(#marks(source) == 0)
    assert(explain.jump(-1))
    assert(vim.api.nvim_buf_get_name(0) == path)
    assert(vim.api.nvim_win_get_cursor(0)[1] == 1)
    explain.clear()
    assert(not explain.status().active and explain.status().locations == 0)
    assert(not review.status().follow, "clear resumed follow")
    assert(explain.show(args).ok)
    review.diff("--- a/source.lua\n+++ b/source.lua\n@@ -1 +1 @@\n-before\n+after\n")
    assert(not explain.status().active and explain.status().locations == 0, "review did not replace explanation")
    local seconds, micros = vim.uv.gettimeofday()
    assert(
        not explain.request({ name = "show_code", arguments = args, deadline = seconds * 1000 + micros / 1000 - 1 }).ok
    )
    explain.close()
    late(args.locations[1], 1)
    assert(not explain.status().enabled)
    print(
        "AGENT_EXPLAIN_OK code + labels / focus / lazy locations / stale + invalid ranges / unsaved safety / edits invalidate / list + clear / expired + stale callbacks"
    )
end, debug.traceback)
explain.close()
review.close()
vim.fn.delete(root, "rf")
if not ok then
    io.stderr:write(err .. "\n")
    vim.cmd.cquit(1)
end
vim.cmd("qa!")
