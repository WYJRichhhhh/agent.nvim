local M = {}

M.defaults = {
    backend = "auto",
    cwd = function()
        return vim.fn.getcwd()
    end,
    env = {},
    window = {
        layout = "float",
        width = 0.85,
        height = 0.85,
        border = "rounded",
        winhighlight = "Normal:AgentNormal,NormalNC:AgentNormal,NormalFloat:AgentNormal,FloatBorder:AgentBorder,FloatTitle:AgentTitle",
    },
    terminal = { start_insert = true, hide_key = false, show_hint = true, capture_mouse = true },
    codex = { enabled = false, node = "node", startup_timeout = 15000 },
    review = {
        follow = true,
        history_limit = 20,
        max_diff_bytes = 2 * 1024 * 1024,
        restrict_to_cwd = true,
        git_fallback = true,
        worktrees = true,
        max_snapshot_bytes = 32 * 1024 * 1024,
    },
    backends = {
        claude = { label = "Claude Code", command = { "claude" }, env = {} },
        codex = { label = "Codex", command = { "codex" }, resume_command = { "codex", "resume" }, env = {} },
    },
}

function M.validate_backend(name, backend)
    assert(
        type(name) == "string" and name:match("^[%w_-]+$"),
        "后端名称只能包含字母、数字、下划线或横线"
    )
    assert(
        type(backend) == "table" and vim.islist(backend.command) and #backend.command > 0,
        "后端 command 必须是非空参数数组"
    )
    for _, arg in ipairs(backend.command) do
        assert(type(arg) == "string" and arg ~= "", "command 参数必须是非空字符串")
    end
    if backend.resume_command ~= nil then
        assert(
            type(backend.resume_command) == "table"
                and vim.islist(backend.resume_command)
                and #backend.resume_command > 0,
            "resume_command 必须是非空参数数组"
        )
        for _, arg in ipairs(backend.resume_command) do
            assert(type(arg) == "string" and arg ~= "", "resume_command 参数必须是非空字符串")
        end
    end
    assert(backend.label == nil or type(backend.label) == "string", "label 必须是字符串")
    M.validate_env(backend.env or {})
end

function M.validate_env(env)
    assert(type(env) == "table", "env 必须是表")
    for key, value in pairs(env) do
        assert(type(key) == "string" and type(value) == "string", "env 的键和值必须是字符串")
    end
end

function M.resolve(opts)
    local result = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
    assert(type(result.backend) == "string", "backend 必须是字符串")
    assert(type(result.cwd) == "function" or type(result.cwd) == "string", "cwd 必须是路径或函数")
    M.validate_env(result.env)
    assert(vim.tbl_contains({ "float", "right", "bottom" }, result.window.layout), "不支持的窗口布局")
    for _, key in ipairs({ "width", "height" }) do
        assert(type(result.window[key]) == "number" and result.window[key] > 0, key .. " 必须大于零")
    end
    assert(type(result.window.winhighlight) == "string", "winhighlight 必须是字符串")
    assert(type(result.terminal.start_insert) == "boolean", "start_insert 必须是布尔值")
    assert(type(result.terminal.show_hint) == "boolean", "show_hint 必须是布尔值")
    assert(type(result.terminal.capture_mouse) == "boolean", "capture_mouse 必须是布尔值")
    local hide_key = result.terminal.hide_key
    assert(hide_key == false or type(hide_key) == "string", "hide_key 必须是字符串或 false")
    assert(type(result.codex.enabled) == "boolean", "codex.enabled 必须是布尔值")
    assert(type(result.codex.node) == "string" and result.codex.node ~= "", "codex.node 必须是命令路径")
    assert(
        type(result.codex.startup_timeout) == "number" and result.codex.startup_timeout >= 1000,
        "startup_timeout 至少为 1000ms"
    )
    for _, key in ipairs({ "follow", "restrict_to_cwd", "git_fallback", "worktrees" }) do
        assert(type(result.review[key]) == "boolean", "review." .. key .. " 必须是布尔值")
    end
    for _, key in ipairs({ "history_limit", "max_diff_bytes", "max_snapshot_bytes" }) do
        assert(
            type(result.review[key]) == "number" and result.review[key] >= 1 and result.review[key] % 1 == 0,
            "review." .. key .. " 必须是正整数"
        )
    end
    for name, backend in pairs(result.backends) do
        M.validate_backend(name, backend)
    end
    assert(result.backend == "auto" or result.backends[result.backend], "默认后端未注册")
    return result
end

M.options = M.resolve()
return M
