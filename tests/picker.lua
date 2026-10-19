vim.opt.rtp:prepend(vim.fn.getcwd())
assert(vim.env.AGENT_TEST_TELESCOPE and vim.env.AGENT_TEST_PLENARY, "Set Telescope and Plenary runtime paths")
vim.opt.rtp:append(vim.env.AGENT_TEST_TELESCOPE)
vim.opt.rtp:append(vim.env.AGENT_TEST_PLENARY)
vim.o.columns = 180
vim.o.lines = 50
local picker = require("agent.picker")
local selected
local entries = {
    { path = "src/one.lua", diff = "@@ -1 +1 @@\n-old\n+new\n" },
    { path = "src/two.lua", diff = "@@ -1 +1 @@\n-before\n+after\n" },
}
picker.select(entries, {
    prompt = "Agent changes",
    format_item = function(e)
        return e.path
    end,
}, function(e)
    selected = e
end)
local prompt = vim.api.nvim_get_current_buf()
local current = require("telescope.actions.state").get_current_picker(prompt)
assert(vim.wait(2000, function()
    return current.manager and current.manager:num_results() == 2
end))
assert(vim.wait(2000, function()
    local buf = current.previewer.state.bufnr
    return buf and vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] == "@@ -1 +1 @@"
end))
assert(vim.bo[current.previewer.state.bufnr].filetype == "diff")
require("telescope.actions").select_default(prompt)
assert(vim.wait(2000, function()
    return selected ~= nil
end))
assert(selected == entries[1])
selected = nil
picker.select(entries, {
    prompt = "Agent changes",
    format_item = function(e)
        return e.path
    end,
}, function(e)
    selected = e
end)
require("telescope.actions").close(vim.api.nvim_get_current_buf())
vim.wait(50, function()
    return false
end)
assert(selected == nil)
print("AGENT_PICKER_OK real Telescope / diff preview / accept / cancel")
vim.cmd("qa!")
