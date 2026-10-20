vim.o.columns = 160
vim.o.lines = 45
vim.o.mouse = ""
local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
local agent = require("agent")
local command = { vim.fn.exepath("python3"), "-u", root .. "/tests/fixtures/fake_cli.py" }
local function setup(capture)
    agent.setup({
        backend = "fake",
        terminal = { start_insert = false, show_hint = false, capture_mouse = capture },
        window = { layout = "right", width = 0.42 },
        backends = { fake = { command = command } },
    })
end
local original = vim.o.mouse
local ok, err = xpcall(function()
    setup(true)
    local editor = vim.api.nvim_get_current_win()
    agent.open()
    assert(vim.o.mouse == "a", "Agent did not capture mouse")
    local job = agent.status().job_id
    local source = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(editor, source)
    assert(vim.api.nvim_get_current_buf() == agent.status().bufnr)
    assert(vim.wait(100, function() return vim.o.mouse == "a" end), "background source buffer update disabled Agent mouse")
    vim.api.nvim_set_current_win(editor)
    assert(vim.o.mouse == "", "editor mouse option not restored")
    agent.open()
    assert(vim.o.mouse == "a")
    agent.hide()
    assert(vim.o.mouse == "")
    vim.o.mouse = "nv"
    agent.open()
    assert(vim.o.mouse == "a")
    agent.hide()
    assert(vim.o.mouse == "nv")
    agent.open()
    vim.o.mouse = "n"
    agent.hide()
    assert(vim.o.mouse == "n", "explicit user change overwritten")
    setup(false)
    agent.open()
    assert(vim.o.mouse == "n", "capture_mouse=false ignored")
    assert(agent.status().job_id == job, "mouse capture restarted CLI")
    agent.stop()
    assert(vim.o.mouse == "n")
    print("AGENT_MOUSE_OK focus / leave / hide / custom option / explicit change / opt-out / singleton")
end, debug.traceback)
agent.stop()
vim.o.mouse = original
if not ok then
    io.stderr:write(err .. "\n")
    vim.cmd.cquit(1)
end
vim.cmd("qa!")
