local M = {}
local config = require("agent.config")
local registry = require("agent.registry")
local window = require("agent.window")
local bridge = require("agent.bridge")
local review = require("agent.review")
local mouse = require("agent.mouse")
local explain = require("agent.explain")
local session, selected, selecting
local generation = 0
local installed = false
local hint_shown = false
local resize_generation = 0

local function warn(message)
    vim.notify(message, vim.log.levels.WARN, { title = "Agent" })
end

local function alive()
    if not session or (session.state ~= "running" and session.state ~= "starting") then
        return false
    end
    if session.state == "starting" then
        return true
    end
    -- 退出回调可能尚未被事件循环处理，查询真实 job 状态避免错误复用。
    return session.job_id and vim.fn.jobwait({ session.job_id }, 0)[1] == -1
end

local function emit(event, value)
    vim.api.nvim_exec_autocmds("User", {
        pattern = event,
        data = { backend = value.backend, cwd = value.cwd, bufnr = value.bufnr, exit_code = value.exit_code },
        modeline = false,
    })
end

local function discard()
    if not session then
        return
    end
    local old = session
    session = nil
    bridge.stop(old)
    mouse.release()
    explain.close()
    review.close()
    window.hide(old)
    if vim.api.nvim_buf_is_valid(old.bufnr) then
        vim.api.nvim_buf_delete(old.bufnr, { force = true })
    end
end

local function launch(name, cwd, command_override)
    local backend = registry.get(name)
    if not backend then
        warn("后端未注册：" .. name)
        return
    end
    local command = command_override or backend.command
    if vim.fn.executable(command[1]) ~= 1 then
        warn("找不到命令：" .. command[1] .. "，请检查 PATH 或配置后端 command")
        return
    end
    discard()
    generation = generation + 1
    local current = {
        id = generation,
        backend = name,
        cwd = cwd,
        state = "starting",
        command = vim.deepcopy(command),
        bufnr = vim.api.nvim_create_buf(false, true),
    }
    session = current
    selected = name
    vim.bo[current.bufnr].bufhidden = "hide"
    vim.bo[current.bufnr].swapfile = false
    vim.b[current.bufnr].agent_session = true
    -- 终端先取得实际窗口尺寸，再启动 CLI，避免首次绘制只有默认的 80 列。
    window.show(current)
    mouse.update(current)
    local env = vim.tbl_extend("force", {}, config.options.env, backend.env or {})
    local function spawn_terminal(argv, terminal_env)
        if session ~= current then
            return
        end
        local ok, job = pcall(vim.api.nvim_buf_call, current.bufnr, function()
            return vim.fn.jobstart(vim.deepcopy(argv), {
                term = true,
                cwd = cwd,
                env = next(terminal_env) and terminal_env or vim.empty_dict(),
                on_exit = function(_, code)
                    vim.schedule(function()
                        if session ~= current then
                            return
                        end
                        bridge.stop(current)
                        current.state, current.exit_code = "exited", code
                        emit("AgentExit", current)
                        if not current.stopping then
                            vim.notify(
                                ("%s 已退出（%d）。:Agent open 可查看输出，:Agent start 可重新启动。"):format(
                                    name,
                                    code
                                ),
                                code == 0 and vim.log.levels.INFO or vim.log.levels.WARN,
                                { title = "Agent" }
                            )
                        end
                    end)
                end,
            })
        end)
        if not ok or job <= 0 then
            discard()
            warn("启动失败：" .. (ok and tostring(job) or tostring(job)))
            return
        end
        current.job_id, current.state = job, "running"
        vim.bo[current.bufnr].filetype = "agent_terminal"
        vim.keymap.set("n", "q", M.hide, { buffer = current.bufnr, desc = "隐藏 Agent，会话继续运行" })
        vim.keymap.set("n", "?", M.help, { buffer = current.bufnr, desc = "Agent 操作帮助" })
        if config.options.terminal.hide_key and config.options.terminal.hide_key ~= "" then
            vim.keymap.set(
                { "n", "t" },
                config.options.terminal.hide_key,
                M.focus,
                { buffer = current.bufnr, desc = "切换 Agent" }
            )
        end
        if config.options.terminal.start_insert then
            vim.cmd.startinsert()
        end
        if config.options.terminal.show_hint and not hint_shown then
            hint_shown = true
            vim.notify(
                "Ctrl-\\ Ctrl-n 后：q 隐藏，? 帮助；:Agent select 切换；:Agent stop 停止。",
                vim.log.levels.INFO,
                { title = "Agent · 操作提示" }
            )
        end
        if current.bridge and config.options.terminal.show_hint then
            vim.notify(
                "修改跟踪：:Agent changes 文件列表；:Agent diff 差异；:Agent follow 跟随开关。",
                vim.log.levels.INFO,
                { title = "Agent Review" }
            )
        end
        emit("AgentStart", current)
    end
    if (name == "codex" or name == "claude") and config.options[name].enabled then
        review.attach(current, config.options.review)
        explain.attach(current, config.options.code)
        bridge.start(current, env, spawn_terminal, function(message)
            if session ~= current or current.stopping then
                return
            end
            current.stopping = true
            bridge.stop(current)
            if current.job_id then
                pcall(vim.fn.jobstop, current.job_id)
            end
            current.state, current.exit_code = "exited", -1
            warn(message .. "；会话已停止，:Agent start 可重试。")
        end)
    else
        spawn_terminal(command, env)
    end
end

local function choose(callback)
    if selecting then
        return
    end
    local names = registry.available()
    if #names == 0 then
        warn("未发现可用的 Agent CLI，请安装 claude 或 codex，或注册自定义后端")
        return
    end
    if #names == 1 then
        selected = names[1]
        callback(selected)
        return
    end
    local token = {}
    selecting = token
    vim.ui.select(names, {
        prompt = "选择 Agent（本次 Neovim 中记住选择）",
        format_item = function(name)
            local label = registry.get(name).label or name
            return session and session.backend == name and (label .. "（当前）") or label
        end,
    }, function(name)
        if selecting ~= token then
            return
        end
        selecting = nil
        if name then
            selected = name
            callback(name)
        end
    end)
end

local function ensure_hooks()
    if installed then
        return
    end
    installed = true
    local group = vim.api.nvim_create_augroup("AgentNvim", { clear = true })
    local mouse_pending = false
    vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter", "TermEnter" }, {
        group = group,
        callback = function()
            mouse.update(session)
            -- Setting a background window's buffer temporarily changes the current
            -- buffer for BufEnter, without a matching event when context is restored.
            -- Reconcile against the real focus after nested window/buffer work ends.
            if not mouse_pending then
                mouse_pending = true
                vim.schedule(function()
                    mouse_pending = false
                    mouse.update(session)
                end)
            end
        end,
    })
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = function()
            -- 等主题完成自己的明暗同步后再更新，不触碰已有进程与会话。
            vim.schedule(window.highlights)
        end,
    })
    vim.api.nvim_create_autocmd("VimResized", {
        group = group,
        callback = function()
            resize_generation = resize_generation + 1
            local generation, current = resize_generation, session
            -- tmux zoom can produce several resize events while Neovim lays out splits.
            vim.defer_fn(function()
                if generation == resize_generation and session == current then
                    pcall(window.resize, current)
                end
            end, 30)
        end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
        group = group,
        callback = function(ev)
            if not session or session.bufnr ~= ev.buf then
                return
            end
            local old = session
            bridge.stop(old)
            mouse.release()
            explain.close()
            review.close()
            session = nil
            if old.job_id and old.state == "running" then
                pcall(vim.fn.jobstop, old.job_id)
            end
        end,
    })
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function()
            selecting = nil
            mouse.release()
            bridge.stop(session)
            bridge.wait(session)
            if session and session.job_id then
                session.stopping = true
                pcall(vim.fn.jobstop, session.job_id)
            end
        end,
    })
end

function M.setup(opts)
    config.options = config.resolve(opts)
    ensure_hooks()
    mouse.update(session)
end

function M.register_backend(name, backend)
    registry.register(name, backend)
end

function M.open(name)
    ensure_hooks()
    if session and vim.api.nvim_buf_is_valid(session.bufnr) then
        if name and name ~= session.backend then
            warn("当前会话属于 " .. session.backend .. "；先 :Agent stop，再 :Agent start " .. name)
            return
        end
        return window.show(session)
    end
    local ok, cwd = pcall(function()
        local value = config.options.cwd
        return vim.fs.normalize(vim.fn.fnamemodify(type(value) == "function" and value() or value, ":p"))
    end)
    if not ok or vim.fn.isdirectory(cwd) ~= 1 then
        warn("Agent 工作目录无效")
        return
    end
    cwd = vim.uv.fs_realpath(cwd) or cwd
    local backend = name or selected or config.options.backend
    if backend == "auto" then
        choose(function(choice)
            launch(choice, cwd)
        end)
    elseif not selecting then
        launch(backend, cwd)
    end
end

function M.hide()
    window.hide(session)
    mouse.update(session)
end

function M.toggle()
    if window.find(session) then
        M.hide()
    else
        M.open()
    end
end

function M.focus()
    local win = window.find(session)
    if win and vim.api.nvim_get_current_win() == win then
        M.hide()
    else
        M.open()
    end
end

-- Return to the existing editor without changing its buffer or the Agent window.
function M.editor()
    if not session then
        return
    end
    local agent_win = window.find(session)
    local target = session.return_win
    local function usable(win)
        return win and vim.api.nvim_win_is_valid(win)
            and win ~= agent_win
            and vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage()
            and vim.api.nvim_win_get_config(win).relative == ""
            and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == ""
    end
    if not usable(target) then
        target = nil
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if usable(win) then
                target = win
                break
            end
        end
    end
    if target then
        vim.cmd.stopinsert()
        vim.api.nvim_set_current_win(target)
    else
        warn("当前标签页没有可返回的代码窗口")
    end
end

function M.stop()
    selecting = nil
    if not session then
        return true
    end
    local old = session
    if alive() and old.job_id then
        old.stopping = true
        local ok, result = pcall(vim.fn.jobstop, old.job_id)
        if not ok or result ~= 1 then
            warn("无法停止 Agent，请检查进程状态")
            return false
        end
        -- 等待旧进程退出后才允许启动新进程，确保只有一个会话。
        if vim.fn.jobwait({ old.job_id }, 1000)[1] == -1 then
            warn("Agent 正在退出，稍后再执行 :Agent stop")
            return false
        end
    end
    discard()
    return true
end

function M.start(name)
    if selecting then
        return
    end
    if alive() then
        warn("已有运行中的会话；请先 :Agent stop")
        return
    end
    if name and not registry.get(name) then
        warn("后端未注册：" .. name)
        return
    end
    discard()
    M.open(name)
end

function M.resume(name)
    ensure_hooks()
    if selecting then
        return
    end
    if alive() then
        warn("会话仍在运行；先在 CLI 中正常退出，再 :Agent resume 恢复历史对话")
        return
    end
    name = name or (session and session.backend) or selected or config.options.backend
    if name == "auto" then
        choose(M.resume)
        return
    end
    local backend = registry.get(name)
    if not backend or not backend.resume_command then
        warn("后端未配置 resume_command：" .. name)
        return
    end
    -- 已退出会话沿用原启动目录，避免编辑器切换目录后选错历史对话。
    local cwd = session and session.backend == name and session.cwd
    if not cwd then
        local ok, value = pcall(function()
            local option = config.options.cwd
            return vim.fs.normalize(vim.fn.fnamemodify(type(option) == "function" and option() or option, ":p"))
        end)
        if not ok or vim.fn.isdirectory(value) ~= 1 then
            warn("Agent 工作目录无效")
            return
        end
        cwd = vim.uv.fs_realpath(value) or value
    end
    launch(name, cwd, backend.resume_command)
end

function M.select()
    local previous_selected = selected
    choose(function(name)
        if not alive() then
            discard()
            M.open(name)
            return
        end
        if session.backend == name then
            window.show(session)
            return
        end
        -- 选择菜单不应提前改变已有会话；取消确认后仍保留原后端。
        selected = previous_selected
        local token = {}
        selecting = token
        local current = session
        vim.ui.select({ "取消", "停止当前会话并切换" }, {
            prompt = ("从 %s 切换到 %s？当前任务和未提交输入会中断，历史对话由 CLI 管理。"):format(
                current.backend,
                name
            ),
        }, function(choice)
            if selecting ~= token then
                return
            end
            selecting = nil
            if choice ~= "停止当前会话并切换" or session ~= current then
                return
            end
            if M.stop() then
                M.open(name)
            end
        end)
    end)
end

function M.gitdiff()
    review.gitdiff()
end

function M.code()
    if explain.focus() then
        return
    end
    review.code()
end

function M.changes()
    review.changes()
end
function M.filediff()
    review.filediff()
end

function M.diff()
    review.diff()
end
function M.follow()
    explain.clear()
    review.follow()
end
function M.pause()
    review.pause()
end
function M.turns()
    review.turns()
end
function M.next()
    if explain.jump(1) then
        return
    end
    review.jump(1)
end
function M.prev()
    if explain.jump(-1) then
        return
    end
    review.jump(-1)
end

function M.locations()
    explain.locations()
end
function M.clear()
    explain.clear()
end

function M.help()
    vim.cmd.stopinsert()
    vim.cmd.help("agent.nvim")
end

function M.status()
    if not session then
        return { state = selecting and "selecting" or "idle", selected = selected }
    end
    return {
        state = session.state,
        backend = session.backend,
        cwd = session.cwd,
        bufnr = session.bufnr,
        job_id = session.job_id,
        exit_code = session.exit_code,
        visible = window.find(session) ~= nil,
        bridge = session.bridge and { state = session.bridge.state, thread_id = session.bridge.thread_id } or nil,
        review = review.status(),
        code = explain.status(),
    }
end

return M
