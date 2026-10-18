local M = {}
local ns = vim.api.nvim_create_namespace("AgentReview")
local state, group, updating = nil, nil, false

local function notify(message)
    vim.notify(message, vim.log.levels.INFO, { title = "Agent Review" })
end

local function valid_win(win)
    return win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == ""
end

local function refresh()
    if state then
        require("agent.window").refresh(state.session)
    end
end

local function clear_marks()
    if not state then
        return
    end
    for buf in pairs(state.marked) do
        if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
        end
    end
    state.marked = {}
end

function M.close()
    clear_marks()
    if group then
        pcall(vim.api.nvim_del_augroup_by_id, group)
        group = nil
    end
    if state and state.preview and vim.api.nvim_buf_is_valid(state.preview) then
        pcall(vim.api.nvim_buf_delete, state.preview, { force = true })
    end
    state = nil
end

function M.attach(session, options)
    M.close()
    state = { session = session, options = options, follow = options.follow, turns = {}, order = {}, marked = {} }
    group = vim.api.nvim_create_augroup("AgentReview", { clear = true })
    vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter", "InsertEnter", "TextChanged", "TextChangedI" }, {
        group = group,
        callback = function(ev)
            if updating or not state or not state.follow then
                return
            end
            if vim.bo[ev.buf].buftype == "" and not vim.b[ev.buf].agent_session then
                state.follow = false
                refresh()
                notify(
                    "已暂停自动跟随，避免打断编辑。:Agent follow 恢复；:Agent changes 查看修改。"
                )
            end
        end,
    })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufReadPost" }, {
        group = group,
        callback = function(ev)
            if not updating and state and state.marked[ev.buf] then
                vim.api.nvim_buf_clear_namespace(ev.buf, ns, 0, -1)
                state.marked[ev.buf] = nil
            end
        end,
    })
end

local function turn(id)
    if not id or not state then
        return
    end
    if not state.turns[id] then
        state.turns[id] = { id = id, files = {}, order = {}, seen = {}, diff = "" }
        state.order[#state.order + 1] = id
        while #state.order > state.options.history_limit do
            state.turns[table.remove(state.order, 1)] = nil
        end
    end
    return state.turns[id]
end

function M.set_roots(roots)
    if not state or not state.options.worktrees then
        return
    end
    state.roots = {}
    for _, root in ipairs(roots or {}) do
        if type(root) == "string" then
            local real = vim.uv.fs_realpath(root)
            if real then
                state.roots[#state.roots + 1] = real
            end
        end
    end
end

local function path_for(path)
    if type(path) ~= "string" or path == "" or path:find("[%z\r\n]") then
        return
    end
    if not vim.startswith(path, "/") and not path:match("^%a:[/\\]") then
        path = state.session.cwd .. "/" .. path
    end
    path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
    local real = vim.uv.fs_realpath(path)
    if not real then
        local parent = vim.uv.fs_realpath(vim.fs.dirname(path))
        if not parent then
            return
        end
        real = parent .. "/" .. vim.fs.basename(path)
    end
    local root = state.session.cwd
    local allowed = real == root or vim.startswith(real, root:gsub("/+$", "") .. "/")
    if not allowed and state.options.worktrees then
        for _, worktree in ipairs(state.roots or {}) do
            if real == worktree or vim.startswith(real, worktree:gsub("/+$", "") .. "/") then
                allowed = true
                break
            end
        end
    end
    if state.options.restrict_to_cwd and not allowed then
        return
    end
    return real
end

-- Parse unified hunks, keeping deleted text as virtual lines above its new-file position.
function M.hunks(diff)
    local result, current, new_line = {}, nil, nil
    for _, line in ipairs(vim.split(diff or "", "\n", { plain = true })) do
        local start = line:match("^@@ %-%d+,?%d* %+(%d+),?%d* @@")
        if start then
            new_line = math.max(1, tonumber(start))
            current = { line = new_line, added = {}, deleted = {} }
            result[#result + 1] = current
        elseif current then
            local prefix = line:sub(1, 1)
            if prefix == "+" then
                current.added[#current.added + 1] = new_line
                new_line = new_line + 1
            elseif prefix == "-" then
                current.deleted[#current.deleted + 1] = { line = new_line, text = line:sub(2) }
            elseif prefix == " " then
                new_line = new_line + 1
            elseif prefix ~= "\\" then
                current = nil
            end
        end
    end
    return result
end

local function target()
    local win = state.session.return_win
    if not valid_win(win) then
        return
    end
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype ~= "" and not vim.b[buf].agent_review then
        return
    end
    if vim.bo[buf].modified then
        return
    end
    return win
end

local function mark(buf, entry)
    clear_marks()
    local count = vim.api.nvim_buf_line_count(buf)
    for _, hunk in ipairs(M.hunks(entry.diff)) do
        for _, line in ipairs(hunk.added) do
            if line <= count then
                vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, { line_hl_group = "DiffAdd", priority = 110 })
            end
        end
        local removed = {}
        for _, item in ipairs(hunk.deleted) do
            local row = math.min(count - 1, math.max(0, item.line - 1))
            removed[row] = removed[row] or { lines = {}, above = item.line <= count }
            local lines = removed[row].lines
            lines[#lines + 1] = { { "- " .. item.text, "DiffDelete" } }
        end
        for row, deletion in pairs(removed) do
            vim.api.nvim_buf_set_extmark(
                buf,
                ns,
                row,
                0,
                { virt_lines = deletion.lines, virt_lines_above = deletion.above, priority = 110 }
            )
        end
    end
    state.marked[buf] = true
end

local function open_file(entry, focus)
    if not state then
        return
    end
    local path = path_for(entry.path)
    if not path or vim.fn.filereadable(path) ~= 1 then
        if focus then
            notify("文件已删除、不可读或超出工作目录；用 :Agent diff 查看补丁。")
        end
        return
    end
    local win = target()
    if not win then
        state.follow = false
        notify("编辑窗口不可用或有未保存修改，已暂停跟随；保存后 :Agent follow。")
        return
    end
    local buf = vim.fn.bufnr(path)
    if buf ~= -1 and vim.bo[buf].modified then
        state.follow = false
        notify("目标文件有未保存修改，未重新加载；:Agent diff 可查看补丁。")
        return
    end
    updating = true
    local ok, err = pcall(function()
        buf = vim.fn.bufadd(path)
        vim.fn.bufload(buf)
        local autoread = vim.bo[buf].autoread
        vim.bo[buf].autoread = true
        local reloaded, reload_error = pcall(vim.api.nvim_buf_call, buf, function()
            vim.cmd("silent checktime")
        end)
        vim.bo[buf].autoread = autoread
        if not reloaded then
            error(reload_error)
        end
        -- A user's FileChangedShell hook may have declined reloading; never mark stale text.
        local disk = vim.fn.readfile(path)
        if not vim.deep_equal(disk, vim.api.nvim_buf_get_lines(buf, 0, -1, false)) then
            error("buffer 与磁盘内容不同，未覆盖 buffer；请先处理外部修改")
        end
        vim.api.nvim_win_set_buf(win, buf)
        local hunks = M.hunks(entry.diff)
        if hunks[1] then
            vim.api.nvim_win_set_cursor(win, { math.min(hunks[1].line, vim.api.nvim_buf_line_count(buf)), 0 })
        end
        if entry.turn_id == state.latest then
            mark(buf, entry)
        else
            clear_marks()
            if focus then
                notify("已打开磁盘上的当前版本；历史差异请用 :Agent filediff 查看。")
            end
        end
        state.current = entry
        if focus then
            vim.cmd.stopinsert()
            vim.api.nvim_set_current_win(win)
        end
    end)
    updating = false
    if not ok then
        state.follow = false
        notify(tostring(err))
    end
end

-- Git quotes unusual paths with C escapes; preserve spaces and UTF-8 bytes.
local function git_path(value)
    if value:sub(1, 1) == '"' then
        value = value:sub(2, -2):gsub("\\([0-7][0-7][0-7])", function(octal)
            return string.char(tonumber(octal, 8))
        end)
        value = value:gsub("\\(.)", function(char)
            return ({ t = "\t", n = "\n", r = "\r", ['"'] = '"', ["\\"] = "\\" })[char] or char
        end)
    end
    if value == "/dev/null" then
        return nil
    end
    return value:gsub("^[ab]/", "")
end

local function aggregate(round, diff)
    local sections, section = {}, nil
    for _, line in ipairs(vim.split(diff, "\n", { plain = true })) do
        if line:match("^diff %-%-git ") then
            section = { lines = {} }
            sections[#sections + 1] = section
        end
        if section then
            section.lines[#section.lines + 1] = line
            if line:match("^%-%-%- ") then
                section.old = git_path(line:sub(5))
            end
            if line:match("^%+%+%+ ") then
                section.new = git_path(line:sub(5))
            end
        end
    end
    for _, part in ipairs(sections) do
        local path = path_for(part.new or part.old)
        if path then
            for _, entry in pairs(round.files) do
                if entry.source ~= "git" and path_for(entry.path) == path then
                    entry.diff = table.concat(part.lines, "\n")
                end
            end
        end
    end
end

function M.event(method, params)
    params.turnId = params.turnId or (params.turn and params.turn.id)
    if not state or not params.turnId then
        return
    end
    local round = turn(params.turnId)
    if method == "turn/started" then
        clear_marks()
        state.latest = round.id
        state.live_turn = round.id
        state.current = nil
    elseif method == "turn/diff/updated" then
        local diff = params.diff
        if type(diff) == "string" and #diff > state.options.max_diff_bytes and not round.large_notice then
            round.large_notice = true
            notify("补丁超过 review.max_diff_bytes，已跳过；可在 CLI 或 git diff 中查看。")
        end
        if type(diff) == "string" and #diff <= state.options.max_diff_bytes then
            round.diff = diff
            aggregate(round, diff)
            if state.follow and state.current and state.current.turn_id == round.id then
                open_file(state.current, false)
            end
        end
    elseif method == "item/completed" and params.item and params.item.type == "fileChange" then
        local item = params.item
        if item.status ~= "completed" or round.seen[item.id] then
            return
        end
        round.seen[item.id] = true
        if item.source == "git" then
            round.has_git = true
        end
        local is_current = not state.live_turn or state.live_turn == round.id
        if is_current then
            state.latest = round.id
        end
        for _, change in ipairs(item.changes or {}) do
            if
                type(change.diff) == "string"
                and #change.diff > state.options.max_diff_bytes
                and not round.large_notice
            then
                round.large_notice = true
                notify("补丁超过 review.max_diff_bytes，已跳过；可在 CLI 或 git diff 中查看。")
            end
            local changed_path = type(change.kind) == "table"
                    and type(change.kind.move_path) == "string"
                    and change.kind.move_path
                or change.path
            if
                type(change.diff) == "string"
                and #change.diff <= state.options.max_diff_bytes
                and path_for(changed_path)
            then
                if change.reverted then
                    round.files[changed_path] = nil
                    if state.last_change and state.last_change.path == changed_path then
                        state.last_change = nil
                    end
                    round.order = vim.tbl_filter(function(path)
                        return path ~= changed_path
                    end, round.order)
                    if state.current and state.current.path == changed_path then
                        state.current = nil
                        clear_marks()
                    end
                else
                    if not round.files[changed_path] then
                        round.order[#round.order + 1] = changed_path
                    end
                    local entry = {
                        source = item.source or "codex",
                        path = changed_path,
                        diff = change.diff,
                        kind = type(change.kind) == "table" and change.kind.type or change.kind,
                        turn_id = round.id,
                    }
                    round.files[changed_path] = entry
                    if is_current then
                        state.last_change = entry
                    end
                    if is_current and (state.follow or not state.current) then
                        state.current = entry
                    end
                    if state.follow and is_current then
                        open_file(entry, false)
                    end
                end
            end
        end
    end
    refresh()
end

function M.follow()
    if not state then
        notify("当前会话未启用 Codex 修改跟踪。")
        return
    end
    state.follow = not state.follow
    notify(
        state.follow and "自动跟随已开启；进入代码窗口或编辑时自动暂停。"
            or "自动跟随已暂停。"
    )
    refresh()
    if state.follow then
        state.view_turn = nil
        state.current = state.last_change
        if state.current and state.current.turn_id == state.latest then
            open_file(state.current, false)
        end
    end
end

function M.pause()
    if state then
        state.follow = false
        refresh()
    end
end

function M.changes(id)
    if not state then
        notify("当前会话未启用 Codex 修改跟踪。")
        return
    end
    local round = state.turns[id or state.view_turn or state.latest]
    if not round or #round.order == 0 then
        notify("这一轮尚无成功的文件修改。")
        return
    end
    local entries = vim.tbl_map(function(path)
        return round.files[path]
    end, round.order)
    local captured = state
    vim.ui.select(entries, {
        prompt = "Agent 修改（选择打开文件，:Agent diff 查看差异）",
        format_item = function(entry)
            return (entry.kind or "update")
                .. (entry.source == "git" and " [Git]" or "")
                .. "  "
                .. vim.fn.fnamemodify(entry.path, ":~:.")
        end,
    }, function(entry)
        if state ~= captured or not entry then
            return
        end
        state.follow = false
        refresh()
        state.current = entry
        if entry.kind == "delete" or entry.turn_id ~= state.latest then
            M.diff(entry.diff)
        else
            open_file(entry, true)
        end
    end)
end

function M.turns()
    if not state then
        notify("当前会话未启用 Codex 修改跟踪。")
        return
    end
    local captured, rounds = state, {}
    for i = #state.order, 1, -1 do
        rounds[#rounds + 1] = state.turns[state.order[i]]
    end
    vim.ui.select(rounds, {
        prompt = "Agent 轮次（当前 Neovim 会话内）",
        format_item = function(round)
            return round.id .. " · " .. #round.order .. " files"
        end,
    }, function(round)
        if state == captured and round then
            state.view_turn = round.id
            M.changes(round.id)
        end
    end)
end

function M.diff(value, root)
    if not state then
        notify("当前会话未启用 Codex 修改跟踪。")
        return
    end
    local round = state.turns[state.view_turn or state.latest]
    local diff = value or (round and not round.has_git and round.diff ~= "" and round.diff)
    if not diff and round then
        local parts = {}
        for _, path in ipairs(round.order) do
            local entry = round.files[path]
            parts[#parts + 1] = vim.startswith(entry.diff, "diff --git ") and entry.diff
                or (
                    "--- "
                    .. vim.json.encode(entry.kind == "add" and "/dev/null" or path)
                    .. "\n+++ "
                    .. vim.json.encode(entry.kind == "delete" and "/dev/null" or path)
                    .. "\n"
                    .. entry.diff
                )
        end
        diff = table.concat(parts, "\n")
    end
    if not diff or diff == "" then
        notify("尚无可显示的 diff。")
        return
    end
    local win = target()
    if not win then
        notify("请先保存编辑窗口中的修改，再查看 diff。")
        return
    end
    state.follow = false
    refresh()
    updating = true
    local previous = vim.api.nvim_win_get_buf(win)
    if not state.preview or not vim.api.nvim_buf_is_valid(state.preview) then
        state.preview = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(state.preview, "agent://review/" .. state.session.bufnr)
        vim.bo[state.preview].buftype = "nofile"
        vim.bo[state.preview].bufhidden = "hide"
        vim.bo[state.preview].swapfile = false
        vim.b[state.preview].agent_review = true
    end
    state.preview_root = root or state.session.cwd
    local buf = state.preview
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(diff, "\n", { plain = true }))
    vim.bo[buf].filetype = "diff"
    vim.bo[buf].modifiable = false
    vim.bo[buf].modified = false
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for i, line in ipairs(vim.split(diff, "\n", { plain = true })) do
        local hl = line:sub(1, 1) == "+" and "DiffAdd"
            or line:sub(1, 1) == "-" and "DiffDelete"
            or line:match("^@@") and "DiffChange"
        if hl then
            vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { line_hl_group = hl })
        end
    end
    state.marked[buf] = true
    if previous ~= buf then
        state.preview_return = previous
    end
    vim.keymap.set("n", "q", function()
        if not state then
            return
        end
        local back = state.preview_return
        if back and vim.api.nvim_buf_is_valid(back) then
            vim.api.nvim_win_set_buf(0, back)
        else
            vim.cmd.enew()
        end
    end, { buffer = buf, desc = "关闭 Agent diff，保留会话" })
    vim.keymap.set("n", "gf", function()
        if not state then
            return
        end
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local cursor = vim.api.nvim_win_get_cursor(0)[1]
        local path, old, first = nil, nil, 1
        for i = cursor, 1, -1 do
            if lines[i]:match("^%+%+%+ ") and not path then
                path = git_path(lines[i]:sub(5))
            end
            if lines[i]:match("^%-%-%- ") and not old then
                old = git_path(lines[i]:sub(5))
            end
            if lines[i]:match("^diff %-%-git ") then
                first = i
                break
            end
        end
        path = path or old
        if not path then
            if state.current then
                open_file(state.current, true)
            end
            return
        end
        if not path:match("^/") and not path:match("^%a:[/\\]") then
            path = state.preview_root .. "/" .. path
        end
        local last = #lines
        for i = cursor + 1, #lines do
            if lines[i]:match("^diff %-%-git ") then
                last = i - 1
                break
            end
        end
        local patch = table.concat(vim.list_slice(lines, first, last), "\n")
        open_file({ path = path, diff = patch }, true)
    end, { buffer = buf, desc = "打开 diff 光标所在文件" })
    vim.cmd.stopinsert()
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_set_current_win(win)
    updating = false
end

function M.gitdiff()
    if not state then
        notify("当前会话未启用修改跟踪。")
        return
    end
    local captured = state
    local roots = { state.session.cwd }
    for _, root in ipairs(state.roots or {}) do
        if not vim.tbl_contains(roots, root) then
            roots[#roots + 1] = root
        end
    end
    vim.ui.select(
        roots,
        { prompt = "Git 工作区差异（含任务开始前已有修改，已跟踪文件）" },
        function(root)
            if state ~= captured or not root then
                return
            end
            state.follow = false
            refresh()
            local parts, bytes, large = {}, 0, false
            vim.system({
                "git",
                "-c",
                "core.fsmonitor=false",
                "-C",
                root,
                "diff",
                "--no-ext-diff",
                "--no-textconv",
                "--no-color",
                "--text",
                "HEAD",
                "--",
            }, {
                text = true,
                timeout = 15000,
                stdout = function(_, data)
                    if not data then
                        return
                    end
                    bytes = bytes + #data
                    if bytes <= captured.options.max_diff_bytes then
                        parts[#parts + 1] = data
                    else
                        large = true
                    end
                end,
            }, function(result)
                vim.schedule(function()
                    if state ~= captured then
                        return
                    end
                    if large then
                        notify("Git diff 超过大小上限，请在终端中查看。")
                    elseif result.code ~= 0 then
                        notify("无法读取 Git diff，请确认所选目录是有提交记录的 Git 工作区。")
                    else
                        local diff = table.concat(parts)
                        if diff == "" then
                            notify("该工作区没有已跟踪文件的差异；未跟踪文件需单独检查。")
                        else
                            M.diff(diff, root)
                        end
                    end
                end)
            end)
        end
    )
end

function M.code()
    if not state then
        notify("当前会话未启用 Codex 修改跟踪。")
        return
    end
    state.follow = false
    refresh()
    if state.current then
        open_file(state.current, true)
    elseif valid_win(state.session.return_win) then
        vim.cmd.stopinsert()
        vim.api.nvim_set_current_win(state.session.return_win)
    end
end

function M.filediff()
    if state and state.current then
        M.diff(state.current.diff)
    else
        notify("请先在 :Agent changes 中选择文件。")
    end
end

function M.jump(direction)
    if not state or not state.current then
        return
    end
    local current_path = vim.api.nvim_buf_get_name(0)
    if path_for(state.current.path) ~= current_path then
        notify("请先在 :Agent changes 中打开对应文件。")
        return
    end
    local cursor = vim.api.nvim_win_get_cursor(0)[1]
    local hunks = M.hunks(state.current.diff)
    if direction < 0 then
        hunks = vim.fn.reverse(hunks)
    end
    for _, hunk in ipairs(hunks) do
        if (direction > 0 and hunk.line > cursor) or (direction < 0 and hunk.line < cursor) then
            vim.api.nvim_win_set_cursor(0, { math.min(hunk.line, vim.api.nvim_buf_line_count(0)), 0 })
            return
        end
    end
end

function M.status()
    if not state then
        return { enabled = false }
    end
    local round = state.turns[state.latest]
    return {
        enabled = true,
        follow = state.follow,
        turn_id = state.latest,
        files = round and #round.order or 0,
        turns = #state.order,
    }
end

return M
