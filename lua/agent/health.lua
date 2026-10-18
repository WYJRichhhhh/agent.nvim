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
    vim.health.info("登录状态由原生 CLI 管理。这里只检查可执行文件，不读取认证信息。")
end
return M
