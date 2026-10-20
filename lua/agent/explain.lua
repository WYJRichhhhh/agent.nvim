local M = {}
local ns = vim.api.nvim_create_namespace("AgentCodeExplanation")
local state, group, updating
local function fail(message)
    return { ok = false, error = message }
end
local function marks_clear()
    if state then
        for buf in pairs(state.marked) do
            if vim.api.nvim_buf_is_valid(buf) then
                vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
            end
        end
        state.marked, state.active = {}, false
    end
end
function M.clear()
    marks_clear()
    if state then
        state.locations, state.index = {}, nil
        state.generation = state.generation + 1
    end
    return { ok = true }
end
function M.close()
    M.clear()
    if group then
        pcall(vim.api.nvim_del_augroup_by_id, group)
    end
    state, group = nil, nil
end
function M.attach(session, options)
    M.close()
    state = { session = session, options = options, locations = {}, marked = {}, title = "", generation = 0 }
    group = vim.api.nvim_create_augroup("AgentCodeExplanation", { clear = true })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufReadPost", "InsertEnter", "BufWipeout" }, {
        group = group,
        callback = function(ev)
            if not updating and state and state.marked[ev.buf] then
                marks_clear()
            end
        end,
    })
end
local function integer(value)
    return type(value) == "number" and value % 1 == 0
end
local function clean(value)
    return (value or ""):gsub("[%c]", " ")
end
local function prepare(location)
    if type(location) ~= "table" then
        return nil, "Each location must be an object"
    end
    local path = require("agent.review").resolve_path(location.file)
    if not path then
        return nil, "File is outside the allowed working directories or no longer exists"
    end
    local stat = vim.uv.fs_stat(path)
    if not stat or stat.type ~= "file" then
        return nil, "File does not exist: " .. path
    end
    if stat.size > state.options.max_file_bytes then
        return nil, "File exceeds code.max_file_bytes"
    end
    local fd = vim.uv.fs_open(path, "r", 438)
    if not fd then
        return nil, "File could not be read"
    end
    local text = vim.uv.fs_read(fd, stat.size + 1, 0)
    vim.uv.fs_close(fd)
    if not text or #text > state.options.max_file_bytes then
        return nil, "File changed or exceeds size limit"
    end
    if text:find("\0", 1, true) then
        return nil, "Binary files cannot be highlighted"
    end
    text = text:gsub("^\239\187\191", ""):gsub("\r\n", "\n"):gsub("\n$", "")
    local lines = vim.split(text, "\n", { plain = true })
    if not vim.islist(location.ranges) or #location.ranges < 1 or #location.ranges > state.options.max_ranges then
        return nil, "Provide a bounded, nonempty ranges array"
    end
    local ranges, count = {}, 0
    for _, range in ipairs(location.ranges) do
        if type(range) ~= "table" then
            return nil, "Each range must be an object"
        end
        local first, last = range.start, range["end"] or range.start
        if not integer(first) or not integer(last) or first < 1 or last < first or last > #lines then
            return nil, "Range is outside the file; read current line numbers before calling show_code"
        end
        count = count + last - first + 1
        if count > state.options.max_highlight_lines then
            return nil, "Too many highlighted lines"
        end
        if range.label ~= nil and (type(range.label) ~= "string" or #range.label > 800) then
            return nil, "Invalid range label"
        end
        local text = table.concat(vim.list_slice(lines, first, last), "\n")
        if range.expected_text ~= nil and range.expected_text ~= text then
            return nil, "Code changed since it was read; expected_text does not match"
        end
        ranges[#ranges + 1] = { start = first, ["end"] = last, label = clean(range.label), expected_text = text }
    end
    return { file = path, ranges = ranges }
end
local function target()
    local win = state.session.return_win
    if not win or not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_config(win).relative ~= "" then
        return
    end
    local buf = vim.api.nvim_win_get_buf(win)
    if buf == state.session.bufnr or (vim.bo[buf].buftype ~= "" and not vim.b[buf].agent_review) then
        return
    end
    return win, buf
end
local function present(location, focus, range_index)
    local win, previous = target()
    if not win then
        return fail("No source editor window is available")
    end
    if vim.bo[previous].modified then
        return fail("Source window has unsaved edits; save them before showing code")
    end
    local mode = vim.api.nvim_get_mode().mode
    if vim.api.nvim_get_current_win() == win and (mode:sub(1, 1) == "i" or mode:sub(1, 1) == "c") then
        return fail("The user is editing; finish the current editor operation first")
    end
    local prepared, error_message = prepare(location)
    if not prepared then
        return fail(error_message)
    end
    local buf = vim.fn.bufnr(prepared.file)
    if buf > 0 and vim.bo[buf].modified then
        return fail("Target buffer has unsaved edits; no content was replaced")
    end
    updating = true
    local ok, err = pcall(function()
        buf = vim.fn.bufadd(prepared.file)
        vim.fn.bufload(buf)
        local autoread = vim.bo[buf].autoread
        vim.bo[buf].autoread = true
        local reloaded, reason = pcall(vim.cmd, "silent checktime " .. buf)
        vim.bo[buf].autoread = autoread
        if not reloaded then
            error(reason)
        end
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        for _, range in ipairs(prepared.ranges) do
            if table.concat(vim.list_slice(lines, range.start, range["end"]), "\n") ~= range.expected_text then
                error("Buffer differs from the requested code; nothing was highlighted")
            end
        end
        require("agent.review").pause()
        require("agent.review").clear_marks()
        marks_clear()
        vim.api.nvim_win_set_buf(win, buf)
        vim.api.nvim_win_set_cursor(win, { prepared.ranges[range_index or 1].start, 0 })
        vim.api.nvim_win_call(win, function()
            vim.cmd("normal! zvzz")
        end)
        vim.api.nvim_set_hl(0, "AgentCodeHighlight", { link = "Visual", default = true })
        vim.api.nvim_set_hl(0, "AgentCodeLabel", { link = "DiagnosticInfo", default = true })
        for _, range in ipairs(prepared.ranges) do
            for line = range.start, range["end"] do
                vim.api.nvim_buf_set_extmark(
                    buf,
                    ns,
                    line - 1,
                    0,
                    { line_hl_group = "AgentCodeHighlight", priority = 120 }
                )
            end
            if range.label ~= "" then
                vim.api.nvim_buf_set_extmark(
                    buf,
                    ns,
                    range.start - 1,
                    0,
                    { virt_text = { { "  ↳ " .. range.label, "AgentCodeLabel" } }, priority = 120 }
                )
            end
        end
        state.marked[buf], state.active = true, true
        if focus then
            vim.cmd.stopinsert()
            vim.api.nvim_set_current_win(win)
        end
    end)
    updating = false
    if not ok then
        return fail(tostring(err))
    end
    return { ok = true, file = prepared.file, ranges = #prepared.ranges, follow_paused = true }
end
function M.show(args)
    if not state or not state.options.enabled then
        return fail("Code explanation is not enabled in this session")
    end
    if
        type(args) ~= "table"
        or not vim.islist(args.locations)
        or #args.locations < 1
        or #args.locations > state.options.max_locations
    then
        return fail("Provide a bounded, nonempty locations array")
    end
    if args.focus ~= nil and type(args.focus) ~= "boolean" then
        return fail("focus must be boolean")
    end
    if args.title ~= nil and (type(args.title) ~= "string" or #args.title > 800) then
        return fail("Invalid title")
    end
    local locations = {}
    for _, location in ipairs(args.locations) do
        local prepared, reason = prepare(location)
        if not prepared then
            return fail(reason)
        end
        locations[#locations + 1] = prepared
    end
    local result = present(locations[1], args.focus == true)
    if result.ok then
        state.generation = state.generation + 1
        state.locations, state.index, state.title, state.range_index = locations, 1, clean(args.title), 1
        result.locations = #locations
    end
    return result
end
function M.focus()
    if not state or not state.active or not state.index then
        return false
    end
    local result = present(state.locations[state.index], true, state.range_index)
    if not result.ok then
        vim.notify(result.error, vim.log.levels.WARN, { title = "Agent Code" })
    end
    return true
end
function M.locations()
    if not state or #state.locations == 0 then
        vim.notify("尚无 Agent 讲解位置；请让 Agent 使用 show_code 展示关键代码。")
        return
    end
    local captured, generation = state, state.generation
    vim.ui.select(state.locations, {
        prompt = state.title ~= "" and state.title or "Agent 讲解位置",
        format_item = function(location)
            return vim.fn.fnamemodify(location.file, ":~:.")
                .. ":"
                .. location.ranges[1].start
                .. "  "
                .. location.ranges[1].label
        end,
    }, function(location, index)
        if not location or captured ~= state or state.generation ~= generation then
            return
        end
        local result = present(location, true)
        if result.ok then
            state.index, state.range_index = index, 1
        else
            vim.notify(result.error, vim.log.levels.WARN, { title = "Agent Code" })
        end
    end)
end
function M.jump(direction)
    if not state or not state.active or not state.index then
        return false
    end
    local positions, current = {}, 1
    for index, location in ipairs(state.locations) do
        for range in ipairs(location.ranges) do
            positions[#positions + 1] = { index = index, range = range }
            if index == state.index and range == (state.range_index or 1) then
                current = #positions
            end
        end
    end
    local next_position = positions[(current - 1 + direction) % #positions + 1]
    local result = present(state.locations[next_position.index], true, next_position.range)
    if result.ok then
        state.index, state.range_index = next_position.index, next_position.range
    else
        vim.notify(result.error, vim.log.levels.WARN, { title = "Agent Code" })
    end
    return true
end

function M.request(value)
    if not state then
        return fail("Agent session has ended")
    end
    local seconds, micros = vim.uv.gettimeofday()
    if type(value.deadline) ~= "number" or seconds * 1000 + micros / 1000 > value.deadline then
        return fail("Editor request expired")
    end
    if value.name == "clear_code" then
        return M.clear()
    end
    if value.name == "show_code" then
        return M.show(value.arguments)
    end
    return fail("Unknown editor tool")
end
function M.status()
    return {
        enabled = state and state.options.enabled or false,
        locations = state and #state.locations or 0,
        active = state and state.active or false,
    }
end
return M
