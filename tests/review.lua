vim.o.columns = 180
vim.o.lines = 50
vim.opt.rtp:prepend(vim.fn.getcwd())
local review = require("agent.review")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
root = vim.uv.fs_realpath(root)
local path = root .. "/example file.txt"
vim.fn.writefile({ "after", "unchanged" }, path)
local editor = vim.api.nvim_get_current_win()
local terminal = vim.api.nvim_create_buf(false, true)
vim.bo[terminal].buftype = "nofile"
local agentwin =
    vim.api.nvim_open_win(terminal, true, { relative = "editor", row = 0, col = 100, width = 60, height = 20 })
local session = { backend = "codex", cwd = root, return_win = editor, bufnr = terminal }
local opts = { follow = true, history_limit = 2, max_diff_bytes = 4096, restrict_to_cwd = true }
local function attach()
    review.attach(session, opts)
end
local function event(id, path_arg, status, diff)
    review.event("item/completed", {
        turnId = "turn1",
        item = {
            type = "fileChange",
            id = id,
            status = status or "completed",
            changes = {
                {
                    path = path_arg or path,
                    kind = { type = "update" },
                    diff = diff or "@@ -1,2 +1,2 @@\n-before\n+after\n unchanged\n",
                },
            },
        },
    })
end
local checks = 0
local function check(name, fn)
    fn()
    checks = checks + 1
    print("PASS " .. name)
end
local ok, err = xpcall(function()
    check("成功事件在编辑窗口打开真实文件，保持 TUI 焦点，添加红绿标记", function()
        attach()
        event("edit1")
        assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(editor)) == path)
        assert(vim.api.nvim_get_current_win() == agentwin)
        local marks = vim.api.nvim_buf_get_extmarks(
            vim.api.nvim_win_get_buf(editor),
            vim.api.nvim_create_namespace("AgentReview"),
            0,
            -1,
            { details = true }
        )
        assert(#marks == 2)
        assert(review.status().files == 1)
    end)
    check("失败和重复事件不重复修改列表，目录外的路径被忽略", function()
        event("failed", path, "failed")
        event("edit1")
        event("outside", "/etc/hosts")
        assert(review.status().files == 1)
    end)
    check("整轮 diff 只读并显示红绿，关闭不停止会话", function()
        review.event("turn/diff/updated", {
            turnId = "turn1",
            diff = "--- a/example file.txt\n+++ b/example file.txt\n@@ -1 +1 @@\n-before\n+after\n",
        })
        review.diff()
        assert(vim.bo.filetype == "diff")
        assert(not vim.bo.modifiable)
        assert(vim.api.nvim_win_is_valid(agentwin))
        assert(not review.status().follow)
        vim.api.nvim_feedkeys("q", "x", false)
        assert(vim.api.nvim_get_current_buf() == vim.api.nvim_win_get_buf(editor))
    end)
    check("阅读不暂停、不抢视图，回到 Agent 后跟到最新修改", function()
        vim.api.nvim_set_current_win(agentwin)
        attach()
        event("before-reading")
        vim.api.nvim_set_current_win(editor)
        vim.api.nvim_win_set_cursor(editor, { 2, 0 })
        local original = vim.api.nvim_win_get_buf(editor)
        local next_path = root .. "/reading.txt"
        vim.fn.writefile({ "new" }, next_path)
        event("while-reading", next_path)
        assert(review.status().follow)
        assert(review.status().files == 2)
        assert(vim.api.nvim_win_get_buf(editor) == original)
        assert(vim.api.nvim_win_get_cursor(editor)[1] == 2)
        vim.api.nvim_set_current_win(agentwin)
        assert(vim.wait(1000, function()
            return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(editor)) == next_path
        end))
        assert(review.status().follow)
        vim.api.nvim_win_set_buf(editor, original)
    end)
    check("隐藏再唤起自动跟到后台修改，不重建会话", function()
        attach()
        event("before-hide")
        local window = require("agent.window")
        window.hide(session)
        assert(review.status().follow)
        local oldbuf = vim.api.nvim_win_get_buf(editor)
        local next_path = root .. "/hidden.txt"
        vim.fn.writefile({ "hidden edit" }, next_path)
        event("while-hidden", next_path)
        assert(vim.api.nvim_win_get_buf(editor) == oldbuf)
        agentwin = window.show(session)
        assert(vim.wait(1000, function()
            return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(editor)) == next_path
        end))
        assert(review.status().follow)
        vim.api.nvim_win_set_buf(editor, vim.fn.bufnr(path))
    end)
    check("开始编辑才暂停，回到 Agent 不自动取消明确暂停", function()
        vim.api.nvim_set_current_win(agentwin)
        attach()
        vim.api.nvim_set_current_win(editor)
        vim.api.nvim_exec_autocmds("InsertEnter", { buffer = vim.api.nvim_get_current_buf() })
        assert(not review.status().follow)
        vim.api.nvim_set_current_win(agentwin)
        vim.wait(50, function()
            return false
        end)
        assert(not review.status().follow)
        attach()
        review.pause()
        vim.api.nvim_set_current_win(editor)
        vim.api.nvim_set_current_win(agentwin)
        vim.wait(50, function()
            return false
        end)
        assert(not review.status().follow)
    end)
    check("目标文件未保存时不覆盖 buffer，不自动跳转", function()
        vim.api.nvim_set_current_win(agentwin)
        attach()
        local buf = vim.api.nvim_win_get_buf(editor)
        vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "unsaved" })
        event("dirty")
        assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "unsaved")
        assert(not review.status().follow)
        vim.bo[buf].modified = false
        vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "after" })
        vim.bo[buf].modified = false
    end)
    check("外部修改自动重载未修改 buffer，保留原 autoread 设置", function()
        vim.api.nvim_set_current_win(agentwin)
        attach()
        local buf = vim.api.nvim_win_get_buf(editor)
        local autoread = vim.bo[buf].autoread
        vim.fn.writefile({ "later", "unchanged" }, path)
        -- Ensure checktime sees a timestamp change even on coarse filesystems.
        vim.uv.fs_utime(path, os.time() + 2, os.time() + 2)
        event("reload", path, "completed", "@@ -1 +1 @@\n-after\n+later\n")
        assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "later")
        assert(vim.bo[buf].autoread == autoread)
    end)
    check("整轮累计 diff 更新多个 hunk，重命名与删除出现在清单", function()
        review.event("turn/diff/updated", {
            turnId = "turn1",
            diff = "diff --git a/example file.txt b/example file.txt\n--- a/example file.txt\n+++ b/example file.txt\n@@ -1 +1 @@\n-before\n+later\n@@ -2 +2 @@\n-old\n+unchanged\n",
        })
        local buf = vim.api.nvim_win_get_buf(editor)
        assert(#vim.api.nvim_buf_get_extmarks(buf, vim.api.nvim_create_namespace("AgentReview"), 0, -1, {}) == 4)
        vim.fn.writefile({ "renamed" }, root .. "/new.txt")
        review.event("item/completed", {
            turnId = "turn1",
            item = {
                id = "rename",
                type = "fileChange",
                status = "completed",
                changes = {
                    {
                        path = root .. "/old.txt",
                        kind = { type = "update", move_path = root .. "/new.txt" },
                        diff = "@@ -1 +1 @@\n-old\n+renamed\n",
                    },
                },
            },
        })
        assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(editor)) == root .. "/new.txt")
        event("delete", root .. "/gone.txt", "completed", "@@ -1 +0,0 @@\n-gone\n")
        assert(review.status().files == 3)
    end)
    check("每轮独立统计，历史有界，晚到选择回调不影响新会话", function()
        review.event("turn/started", { turn = { id = "turn2" } })
        assert(review.status().files == 0)
        review.event("turn/started", { turn = { id = "turn3" } })
        assert(review.status().turns == 2)
        local original = vim.ui.select
        local callback
        vim.ui.select = function(_, _, cb)
            callback = cb
        end
        review.turns()
        review.close()
        attach()
        callback({ id = "turn1" })
        assert(review.status().turns == 0)
        vim.ui.select = original
    end)
    check("批量修改仅加载最后一个目标，避免为全部文件启动 LSP", function()
        vim.api.nvim_set_current_win(agentwin)
        attach()
        local changes = {}
        for i = 1, 20 do
            local file = root .. "/batch-" .. i .. ".txt"
            vim.fn.writefile({ "new content" }, file)
            changes[#changes + 1] =
                { path = file, kind = { type = "update" }, diff = "@@ -1 +1 @@\n-old\n+new content\n" }
        end
        local item = { id = "batch", type = "fileChange", status = "completed", changes = changes }
        review.event("item/completed", { turnId = "batch-turn", item = item })
        local loaded = 0
        for _, change in ipairs(changes) do
            local buf = vim.fn.bufnr(change.path)
            if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
                loaded = loaded + 1
            end
        end
        assert(loaded == 1, "batch loaded " .. loaded .. " buffers")
        assert(review.status().files == 20)
        assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(editor)) == changes[#changes].path)
    end)
    check("会话文件列表跨轮去重，选中当前文件显示行内差异", function()
        vim.api.nvim_set_current_win(agentwin)
        attach()
        event("session-first")
        review.event("turn/started", { turn = { id = "turn2" } })
        local next_path = root .. "/second.txt"
        vim.fn.writefile({ "second" }, next_path)
        review.event("item/completed", {
            turnId = "turn2",
            item = {
                type = "fileChange",
                id = "second",
                status = "completed",
                changes = {
                    { path = next_path, kind = { type = "update" }, diff = "@@ -1 +1 @@\n-first\n+second\n" },
                    { path = path, kind = { type = "update" }, diff = "@@ -1 +1 @@\n-before\n+later\n" },
                },
            },
        })
        local original = vim.ui.select
        vim.ui.select = function(entries, _, cb)
            assert(#entries == 2)
            assert(entries[1].turn_id == "turn2")
            cb(entries[1])
        end
        review.changes()
        vim.ui.select = original
        assert(not review.status().follow)
        local buf = vim.api.nvim_win_get_buf(editor)
        assert(vim.api.nvim_get_current_win() == editor)
        assert(vim.api.nvim_buf_get_name(buf) == next_path)
        assert(#vim.api.nvim_buf_get_extmarks(buf, vim.api.nvim_create_namespace("AgentReview"), 0, -1, {}) == 2)
    end)
    check("多 hunk 及删除文件可解析，停止清理高亮", function()
        local hunks = review.hunks("@@ -1 +0,0 @@\n-gone\n@@ -4,0 +4 @@\n+new\n")
        assert(#hunks == 2 and #hunks[1].deleted == 1 and hunks[2].added[1] == 4)
        review.close()
        assert(not review.status().enabled)
    end)
end, debug.traceback)
review.close()
vim.fn.delete(root, "rf")
if not ok then
    io.stderr:write(err .. "\n")
    vim.cmd.cquit(1)
end
print("AGENT_REVIEW_OK " .. checks .. " checks")
vim.cmd("qa!")
