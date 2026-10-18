local M = {}
function M.check()
    vim.health.start("agent.nvim")
    if vim.fn.has("nvim-0.11") == 1 then
        vim.health.ok("Neovim 版本支持原生终端接口")
    else
        vim.health.error("需要 Neovim 0.11 或更新版本")
    end
    local found = require("agent.registry").available()
    for name, backend in pairs(require("agent.config").options.backends) do
        if vim.tbl_contains(found, name) then
            vim.health.ok(name .. "：" .. vim.fn.exepath(backend.command[1]))
        else
            vim.health.warn(name .. " 不可用：" .. backend.command[1])
        end
    end
    if #found == 0 then
        vim.health.error("至少需要一个可用后端")
    end
    if require("agent.config").options.codex.enabled then
        local node = require("agent.config").options.codex.node
        if vim.fn.executable(node) == 1 then
            local result = vim.system({ node, "--version" }, { text = true }):wait()
            local major = tonumber((result.stdout or ""):match("v(%d+)"))
            if major and major >= 22 then
                vim.health.ok("Codex bridge Node.js: " .. vim.trim(result.stdout))
            else
                vim.health.error("Codex bridge 需要 Node.js 22+")
            end
        else
            vim.health.error("Codex bridge 找不到 Node.js: " .. node)
        end
        if require("agent.config").options.review.git_fallback then
            if vim.fn.executable("git") == 1 then
                vim.health.ok("Git fallback 可用")
            else
                vim.health.warn("找不到 git；脚本写入兜底不可用，仍可接收原生修改事件")
            end
        end
        vim.health.info(
            "Codex bridge 需要支持 --remote / capability-token 的 CLI；已验证 0.163.0。Claude 不使用 bridge。"
        )
    end
    vim.health.info("登录状态由原生 CLI 管理。这里只检查可执行文件，不读取认证信息。")
end
return M
