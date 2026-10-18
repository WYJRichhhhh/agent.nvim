local M = {}
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))))

function M.start(session, env, ready, failure)
    local options = require("agent.config").options.codex
    local node = vim.fn.exepath(options.node)
    if node == "" then
        failure("Codex 修改跟踪需要 Node.js 22+；安装后重试，或设置 codex.enabled=false。")
        return
    end
    local bridge = { pending = "", stopped = false, state = "starting" }
    session.bridge = bridge
    local function fail(message)
        if bridge.stopped then
            return
        end
        bridge.state = "error"
        failure(message)
    end
    local function message(value)
        if bridge.stopped then
            return
        end
        if value.type == "ready" then
            bridge.state = "ready"
            local command = vim.deepcopy(session.command)
            vim.list_extend(
                command,
                { "--remote", value.endpoint, "--remote-auth-token-env", "AGENT_NVIM_SERVER_TOKEN" }
            )
            ready(command, vim.tbl_extend("force", {}, env, { AGENT_NVIM_SERVER_TOKEN = value.token }))
        elseif value.type == "thread" then
            bridge.thread_id = value.threadId
            bridge.state = value.state
        elseif value.type == "roots" then
            require("agent.review").set_roots(value.roots)
        elseif value.type == "event" then
            require("agent.review").event(value.method, value.params)
        elseif value.type == "warning" then
            vim.notify(value.message, vim.log.levels.WARN, { title = "Agent Codex" })
        elseif value.type == "error" then
            fail(value.message)
        end
    end
    bridge.job = vim.fn.jobstart({ node, root .. "/scripts/codex-bridge.mjs" }, {
        cwd = session.cwd,
        env = next(env) and env or vim.empty_dict(),
        on_stdout = function(_, data)
            if bridge.stopped then
                return
            end
            local text = bridge.pending .. table.concat(data, "\n")
            local lines = vim.split(text, "\n", { plain = true })
            bridge.pending = table.remove(lines)
            if #bridge.pending > 40 * 1024 * 1024 then
                fail("Codex bridge message exceeds limit")
                return
            end
            for _, line in ipairs(lines) do
                local ok, value = pcall(vim.json.decode, line)
                if ok and type(value) == "table" then
                    message(value)
                end
            end
        end,
        on_stderr = function() end,
        on_exit = function(_, code)
            if not bridge.stopped then
                fail("Codex bridge 已退出（" .. code .. "）；请检查 :Agent health。")
            end
        end,
    })
    if bridge.job <= 0 then
        fail("无法启动 Codex bridge")
        return
    end
    vim.fn.chansend(bridge.job, vim.json.encode({
        type = "start",
        executable = session.command[1],
        cwd = session.cwd,
        timeout = options.startup_timeout,
        review = require("agent.config").options.review,
    }) .. "\n")
end

function M.stop(session)
    local bridge = session and session.bridge
    if not bridge or bridge.stopped then
        return
    end
    bridge.stopped = true
    bridge.state = "stopped"
    if bridge.job and bridge.job > 0 then
        pcall(vim.fn.chansend, bridge.job, '{"type":"stop"}\n')
        pcall(vim.fn.chanclose, bridge.job, "stdin")
        -- Let the helper reap its App Server before terminating an unresponsive helper.
        local job = bridge.job
        vim.defer_fn(function()
            if vim.fn.jobwait({ job }, 0)[1] == -1 then
                pcall(vim.fn.jobstop, job)
            end
        end, 2000)
    end
end

function M.wait(session)
    local bridge = session and session.bridge
    if bridge and bridge.job and bridge.job > 0 then
        pcall(vim.fn.jobwait, { bridge.job }, 1800)
    end
end

return M
